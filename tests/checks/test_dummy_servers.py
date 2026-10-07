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
