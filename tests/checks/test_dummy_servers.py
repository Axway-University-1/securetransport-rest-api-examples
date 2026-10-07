#!/usr/bin/env python3
"""
Check the dummy servers the integration checks point SecureTransport at
(tests/integration/lib/dummy_servers.py): each answers the calls ST makes, the
way the real service does, and records them. Talks to them on this machine
only, and stops them again.

Runs offline. Exit code 0 means clean.
"""
import json
import os
import socket
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "integration", "lib"))
import dummy_servers  # noqa: E402

failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1


def call(method, url, body=None, headers=None):
    request = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.read(), dict(response.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers)


print("=== FakeVault ===")
with dummy_servers.FakeVault() as vault:
    base = "http://127.0.0.1:%d" % vault.port
    status, body, _ = call("POST", base + "/v1/auth/approle/login", b'{"role_id":"r","secret_id":"s"}',
                           {"Content-Type": "application/json"})
    token = json.loads(body)["auth"]["client_token"] if status == 200 else None
    check("an AppRole login answers a client token at $.auth.client_token", token == dummy_servers.FakeVault.TOKEN, status)
    status, body, _ = call("GET", base + "/v1/secret/data/example/db", headers={"X-Vault-Token": token or ""})
    check("a KV v2 read answers the secret at $.data.data",
          status == 200 and json.loads(body)["data"]["data"]["username"] == "example_user", (status, body))
    status, _, _ = call("GET", base + "/v1/secret/data/example/db", headers={"X-Vault-Token": "wrong"})
    check("a wrong token answers 403", status == 403, status)
    status, _, _ = call("GET", base + "/v1/secret/data/example/none", headers={"X-Vault-Token": token or ""})
    check("an unknown secret answers 404", status == 404, status)
    check("it records the requests, with the login body",
          [r["method"] for r in vault.requests] == ["POST", "GET", "GET", "GET"]
          and b'"role_id"' in vault.requests[0]["body"], [r["path"] for r in vault.requests])

print("=== FakeS3 ===")
with dummy_servers.FakeS3() as s3:
    base = "http://127.0.0.1:%d" % s3.port
    check("HEAD on the bucket answers 200", call("HEAD", base + "/example-bucket")[0] == 200)
    check("HEAD on another bucket answers 404", call("HEAD", base + "/no-such-bucket")[0] == 404)
    status, _, headers = call("PUT", base + "/example-bucket/a/file.txt", b"hello", {"Authorization": "AWS4-HMAC-SHA256 any"})
    check("PUT stores an object, with an ETag, whatever the credentials", status == 200 and "ETag" in headers, status)
    check("GET reads it back", call("GET", base + "/example-bucket/a/file.txt")[1] == b"hello")
    status, body, _ = call("GET", base + "/example-bucket?list-type=2")
    check("listing the bucket shows it", status == 200 and b"<Key>a/file.txt</Key>" in body, body)
    check("DELETE removes it", call("DELETE", base + "/example-bucket/a/file.txt")[0] == 204
          and call("HEAD", base + "/example-bucket/a/file.txt")[0] == 404)

print("=== TcpSink ===")
with dummy_servers.TcpSink() as sink:
    with socket.create_connection(("127.0.0.1", sink.port), timeout=10) as conn:
        conn.sendall(b"<TrkDescriptor>HEARTBEAT</TrkDescriptor>")
    check("it keeps what a client sends", sink.wait_for(b"HEARTBEAT", 5), sink.received())
    check("it records the connection", len(sink.connections) == 1 and sink.connections[0]["client"] == "127.0.0.1")
    check("wait_for gives up on what never comes", not sink.wait_for(b"NEVER", 1))

print("=== FakeIcap ===")
HTTP_HEAD = b"POST /f.txt HTTP/1.1\r\nHost: sthost\r\n\r\n"


def icap_head(preview=None):
    extra = "Preview: %d\r\n" % preview if preview is not None else ""
    return ("REQMOD icap://127.0.0.1/AVSCAN ICAP/1.0\r\nHost: 127.0.0.1\r\nAllow: 204\r\n%sEncapsulated: req-hdr=0, req-body=%d\r\n\r\n"
            % (extra, len(HTTP_HEAD))).encode() + HTTP_HEAD


def read_icap(conn, until=b"\r\n\r\n"):
    data = b""
    while until not in data:
        chunk = conn.recv(65536)
        if not chunk:
            break
        data += chunk
    return data


with dummy_servers.FakeIcap() as icap:
    with socket.create_connection(("127.0.0.1", icap.port), timeout=10) as conn:
        conn.sendall(b"OPTIONS icap://127.0.0.1/AVSCAN ICAP/1.0\r\nHost: 127.0.0.1\r\n\r\n")
        answer = read_icap(conn)
        check("OPTIONS answers 200 with the methods, a preview size and Allow: 204",
              answer.startswith(b"ICAP/1.0 200 OK") and b"Methods: REQMOD, RESPMOD" in answer and b"Preview: 1024" in answer
              and b"Allow: 204" in answer, answer)
        conn.sendall(icap_head(preview=10) + b"4\r\nabcd\r\n0; ieof\r\n\r\n")
        answer = read_icap(conn)
        check("a clean file whose whole body is in the preview (ieof) is let through with 204", answer.startswith(b"ICAP/1.0 204"), answer)
        marked = b"some text EICAR-ICAP-TEST in it...."
        conn.sendall(icap_head(preview=40) + b"%x\r\n" % len(marked) + marked + b"\r\n0; ieof\r\n\r\n")
        answer = read_icap(conn, b"0\r\n\r\n")
        check("a file with the marker is blocked: 200 with an encapsulated HTTP 403",
              answer.startswith(b"ICAP/1.0 200 OK") and b"HTTP/1.1 403 Forbidden" in answer, answer)
        conn.sendall(icap_head(preview=4) + b"4\r\nabcd\r\n0\r\n\r\n")
        answer = read_icap(conn)
        check("a preview that is not the whole file is answered 100 Continue", answer.startswith(b"ICAP/1.0 100 Continue"), answer)
        conn.sendall(b"6\r\nefghij\r\n0\r\n\r\n")
        answer = read_icap(conn)
        check("and once the rest has been sent, with 204", answer.startswith(b"ICAP/1.0 204"), answer)
    deadline = time.time() + 5
    while len(icap.requests) < 3 and time.time() < deadline:
        time.sleep(0.1)
    check("it records each scan: the body, whether it was blocked, and the ICAP headers",
          [(r["body"], r["blocked"]) for r in icap.requests] == [(b"abcd", False), (b"some text EICAR-ICAP-TEST in it....", True), (b"abcdefghij", False)]
          and icap.requests[0]["icap_headers"].get("allow") == "204" and len(icap.options) == 1, [(r["body"], r["blocked"]) for r in icap.requests])
icap_port = icap.port
try:
    socket.create_connection(("127.0.0.1", icap_port), timeout=2).close()
    icap_stopped = False
except OSError:
    icap_stopped = True
check("it stops listening when the with block ends", icap_stopped)

port = sink.port
try:
    socket.create_connection(("127.0.0.1", port), timeout=2).close()
    stopped = False
except OSError:
    stopped = True
check("the sink stops listening when the with block ends", stopped)

print()
print("test_dummy_servers: %s" % ("PASS" if not failed else "FAIL"))
sys.exit(1 if failed else 0)
