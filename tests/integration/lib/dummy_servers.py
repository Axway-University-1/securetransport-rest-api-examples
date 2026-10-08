#!/usr/bin/env python3
"""
Throwaway stand-ins for the outside systems a SecureTransport server talks to,
so the integration checks can exercise a configuration end to end without a
real HashiCorp Vault, S3 bucket or Axway Sentinel:

- FakeVault  answers an AppRole login and KV version 2 secret reads, the two
             calls an ST external store makes.
- FakeToken  an OAuth token endpoint: answers any POST (a client credentials request) with a status
             and body you set, and records the form it received. For the Amplify Platform login of
             the usage report's connection test.
- FakeS3     answers path-style S3 requests with any credentials, keeping
             objects in memory - enough for an S3 storage profile's test.
- TcpSink    accepts connections and keeps what it receives, for Sentinel.
- JunkServer accepts a connection, sends one line that no SSH, FTP or HTTP server would send, and
             closes it: a "partner" that is not what its site says, so a connection test fails at once
             (a TcpSink would keep the test waiting for more than 30 seconds).
- SlowProxy  a TCP proxy that passes the bytes through at a limited rate, in both
             directions, so a transfer through it lasts as long as you need; close()
             cuts every connection, which aborts the transfer.
- CapturingProxy  a TCP proxy that passes the bytes through unchanged and keeps a copy of each
             direction of each connection, to see what a transfer puts on the wire.
- FakeIcap   an ICAP server: answers OPTIONS, reads a REQMOD or RESPMOD request
             with its preview, and either lets the file through (204) or blocks
             it with a 403 when it holds the marker text. Records each request.

Each runs in a background thread on a port the system picks, listening on
every interface, and records the requests it saw. The ST server must be able
to reach this machine: set st_callback_host in integration.conf to this
machine's address as the server sees it.

    with dummy_servers.FakeVault() as vault:
        url = "http://%s:%d" % (callback_host, vault.port)
        ...
        assert any(r["path"].endswith("/approle/login") for r in vault.requests)

Run on its own to keep one up by hand:  python3 dummy_servers.py vault|token|s3|sink|junk|icap [PORT]
"""
import hashlib
import json
import socket
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class _HttpDummy:
    """An HTTP server in a thread, recording every request."""

    def __init__(self, port=0):
        self.requests = []
        dummy = self

        class Handler(self.handler):
            protocol_version = "HTTP/1.1"

            def log_message(self, fmt, *args):
                pass

            def record(self, body=b""):
                dummy.requests.append({"method": self.command, "path": self.path, "client": self.client_address[0],
                                       "headers": dict(self.headers), "body": body})

        self.server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
        self.server.dummy = self
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()


class _Reply(BaseHTTPRequestHandler):
    def reply(self, code, body=b"", ctype="application/json", extra=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def body(self):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            data = b""
            while True:
                size = int(self.rfile.readline().split(b";")[0].strip() or b"0", 16)
                if size == 0:
                    self.rfile.readline()
                    return data
                data += self.rfile.read(size)
                self.rfile.readline()
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))


class _VaultHandler(_Reply):
    def do_POST(self):
        body = self.body()
        self.record(body)
        if self.path.split("?")[0].endswith("/auth/approle/login"):
            return self.reply(200, {"auth": {"client_token": FakeVault.TOKEN, "lease_duration": 3600}})
        self.reply(404, {"errors": []})

    def do_GET(self):
        self.record()
        if self.headers.get("X-Vault-Token") != FakeVault.TOKEN:
            return self.reply(403, {"errors": ["permission denied"]})
        # /v1/<mount>/data/<secret path>
        secret = self.path.split("?")[0].split("/data/", 1)[-1]
        if secret in self.server.dummy.secrets:
            return self.reply(200, {"data": {"data": self.server.dummy.secrets[secret], "metadata": {"version": 1}}})
        self.reply(404, {"errors": []})


class FakeVault(_HttpDummy):
    """HashiCorp Vault: POST /v1/auth/approle/login, then GET /v1/<mount>/data/<path>
    with the X-Vault-Token it handed out. Any role_id and secret_id log in."""
    handler = _VaultHandler
    TOKEN = "fake-vault-token"

    def __init__(self, port=0, secrets=None):
        super().__init__(port)
        self.secrets = secrets if secrets is not None else {
            "example/db": {"username": "example_user", "password": "example_password"}}


class _TokenHandler(_Reply):
    def do_POST(self):
        body = self.body()
        self.record(body)
        dummy = self.server.dummy
        self.reply(dummy.status, dummy.answer)

    def do_GET(self):
        self.record()
        self.reply(404, {"error": "not found"})


class FakeToken(_HttpDummy):
    """An OAuth token endpoint. Every POST gets `status` and `answer` (change them between calls to
    make it refuse); each request is recorded, and form(n) reads request n's form fields."""
    handler = _TokenHandler

    def __init__(self, port=0, status=401, answer=None):
        super().__init__(port)
        self.status = status
        self.answer = answer if answer is not None else {"error": "invalid_client", "error_description": "Invalid client"}

    def form(self, index=-1):
        from urllib.parse import parse_qs
        return {k: v[0] for k, v in parse_qs(self.requests[index]["body"].decode()).items()}


class _S3Handler(_Reply):
    def _parts(self):
        path, _, query = self.path.partition("?")
        bucket, _, key = path.lstrip("/").partition("/")
        return bucket, key, query

    def _error(self, code, s3code):
        self.reply(code, ('<?xml version="1.0"?><Error><Code>%s</Code></Error>' % s3code).encode(), "application/xml")

    def do_HEAD(self):
        self.record()
        bucket, key, _ = self._parts()
        objects = self.server.dummy.buckets.get(bucket)
        if objects is None:
            return self._error(404, "NoSuchBucket")
        if not key:
            return self.reply(200, ctype="application/xml", extra={"x-amz-bucket-region": "us-east-1"})
        if key not in objects:
            return self._error(404, "NoSuchKey")
        self.reply(200, objects[key], "application/octet-stream")

    def do_GET(self):
        self.record()
        bucket, key, query = self._parts()
        objects = self.server.dummy.buckets.get(bucket)
        if objects is None:
            return self._error(404, "NoSuchBucket")
        if not key:
            if "location" in query:
                return self.reply(200, b'<?xml version="1.0"?><LocationConstraint>us-east-1</LocationConstraint>',
                                  "application/xml")
            now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
            items = "".join("<Contents><Key>%s</Key><Size>%d</Size><LastModified>%s</LastModified></Contents>"
                            % (k, len(v), now) for k, v in objects.items())
            return self.reply(200, ('<?xml version="1.0"?><ListBucketResult><Name>%s</Name><KeyCount>%d</KeyCount>'
                                    "<IsTruncated>false</IsTruncated>%s</ListBucketResult>"
                                    % (bucket, len(objects), items)).encode(), "application/xml")
        if key not in objects:
            return self._error(404, "NoSuchKey")
        self.reply(200, objects[key], "application/octet-stream")

    def do_PUT(self):
        data = self.body()
        self.record(data)
        bucket, key, _ = self._parts()
        if bucket not in self.server.dummy.buckets:
            return self._error(404, "NoSuchBucket")
        self.server.dummy.buckets[bucket][key] = data
        self.reply(200, ctype="application/xml", extra={"ETag": '"%s"' % hashlib.md5(data).hexdigest()})

    def do_DELETE(self):
        self.record()
        bucket, key, _ = self._parts()
        self.server.dummy.buckets.get(bucket, {}).pop(key, None)
        self.reply(204, ctype="application/xml")


class FakeS3(_HttpDummy):
    """S3, path style (http://host:port/<bucket>/<key>): HEAD and list a bucket,
    PUT, GET, HEAD and DELETE objects. Signatures are not checked."""
    handler = _S3Handler

    def __init__(self, port=0, buckets=("example-bucket",)):
        super().__init__(port)
        self.buckets = {name: {} for name in buckets}


class TcpSink:
    """Accepts TCP connections and keeps everything it receives, per connection."""

    def __init__(self, port=0):
        self.connections = []
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("0.0.0.0", port))
        self.sock.listen()
        self.port = self.sock.getsockname()[1]
        self.thread = threading.Thread(target=self._accept, daemon=True)

    def _accept(self):
        while True:
            try:
                conn, addr = self.sock.accept()
            except OSError:
                return
            record = {"client": addr[0], "data": b""}
            self.connections.append(record)
            threading.Thread(target=self._read, args=(conn, record), daemon=True).start()

    @staticmethod
    def _read(conn, record):
        conn.settimeout(300)
        try:
            while True:
                data = conn.recv(65536)
                if not data:
                    break
                record["data"] += data
        except OSError:
            pass
        conn.close()

    def received(self):
        return b"".join(c["data"] for c in self.connections)

    def wait_for(self, text, seconds):
        """True once text (bytes) has arrived, waiting up to seconds."""
        deadline = time.time() + seconds
        while time.time() < deadline:
            if text in self.received():
                return True
            time.sleep(1)
        return False

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        # On Linux close() alone leaves accept() blocked and the port listening
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()
        self.thread.join(5)


class JunkServer:
    """Answers every connection with `line` (default: a text no protocol uses) and closes it.
    connections counts them."""

    def __init__(self, port=0, line=b"this is not a partner\r\n"):
        self.line = line
        self.connections = 0
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("0.0.0.0", port))
        self.sock.listen()
        self.port = self.sock.getsockname()[1]
        self.thread = threading.Thread(target=self._accept, daemon=True)

    def _accept(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            self.connections += 1
            try:
                conn.sendall(self.line)
            except OSError:
                pass
            conn.close()

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        # On Linux close() alone leaves accept() blocked and the port listening
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()
        self.thread.join(5)


class SlowProxy:
    """
    Forwards each connection to target_host:target_port, passing at most `rate` bytes
    a second each way. Counts the connections in `connections`. close() stops
    listening and cuts the ones that are open.
    """

    def __init__(self, target_host, target_port, rate=200 * 1024, port=0):
        self.target = (target_host, target_port)
        self.rate = rate
        self.connections = 0
        self._open = []
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("0.0.0.0", port))
        self.sock.listen()
        self.port = self.sock.getsockname()[1]
        self.thread = threading.Thread(target=self._accept, daemon=True)

    def _accept(self):
        while True:
            try:
                client, _ = self.sock.accept()
            except OSError:
                return
            self.connections += 1
            try:
                upstream = socket.create_connection(self.target, timeout=15)
                upstream.settimeout(None)
            except OSError:
                client.close()
                continue
            self._open += [client, upstream]
            for source, sink in ((client, upstream), (upstream, client)):
                threading.Thread(target=self._pump, args=(source, sink), daemon=True).start()

    def _pump(self, source, sink):
        try:
            while True:
                data = source.recv(8192)
                if not data:
                    break
                sink.sendall(data)
                time.sleep(len(data) / float(self.rate))
        except OSError:
            pass
        for end in (source, sink):
            try:
                end.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

    def close(self):
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()
        for end in self._open:
            try:
                end.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            end.close()
        self._open = []

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.close()
        self.thread.join(5)


class CapturingProxy:
    """
    A TCP proxy that passes the bytes through unchanged and keeps a copy of them. connections holds
    one dict per connection through it: {"to_target": bytes the client sent, "to_client": bytes the
    target answered}, in the order the connections were made. to_target_all() and to_client_all()
    join them. A client that keeps its connection open for the next transfer (SecureTransport does)
    makes no new record, so reset() starts every open connection a new record and forgets the old
    ones: what is read after it is what passed since. wait_idle(seconds) waits until nothing has
    moved for that long. close() cuts what is open.
    """

    def __init__(self, target_host, target_port, port=0):
        self.target = (target_host, target_port)
        self.connections = []
        self._live = []
        self._open = []
        self._last = time.time()
        self._lock = threading.Lock()
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("0.0.0.0", port))
        self.sock.listen()
        self.port = self.sock.getsockname()[1]
        self.thread = threading.Thread(target=self._accept, daemon=True)

    @staticmethod
    def _new_record():
        return {"to_target": bytearray(), "to_client": bytearray()}

    def _accept(self):
        while True:
            try:
                client, _ = self.sock.accept()
            except OSError:
                return
            try:
                upstream = socket.create_connection(self.target, timeout=15)
                upstream.settimeout(None)
            except OSError:
                client.close()
                continue
            conn = {"record": self._new_record()}
            with self._lock:
                self.connections.append(conn["record"])
                self._live.append(conn)
                self._open += [client, upstream]
            for source, sink, key in ((client, upstream, "to_target"), (upstream, client, "to_client")):
                threading.Thread(target=self._pump, args=(source, sink, conn, key), daemon=True).start()

    def _pump(self, source, sink, conn, key):
        try:
            while True:
                data = source.recv(65536)
                if not data:
                    break
                with self._lock:
                    conn["record"][key].extend(data)
                    self._last = time.time()
                sink.sendall(data)
        except OSError:
            pass
        for end in (source, sink):
            try:
                end.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

    def to_target_all(self):
        with self._lock:
            return b"".join(bytes(c["to_target"]) for c in self.connections)

    def to_client_all(self):
        with self._lock:
            return b"".join(bytes(c["to_client"]) for c in self.connections)

    def reset(self):
        """Forget what was captured. Connections still open go on into a new record each."""
        with self._lock:
            self.connections = []
            for conn in self._live:
                conn["record"] = self._new_record()
                self.connections.append(conn["record"])

    def wait_idle(self, seconds=2, limit=30):
        """Wait until no byte has passed for `seconds`, at most `limit` seconds; True if it went quiet."""
        deadline = time.time() + limit
        while time.time() < deadline:
            if time.time() - self._last >= seconds:
                return True
            time.sleep(0.2)
        return False

    def drop_connections(self):
        """Cut every connection that is open, and keep listening: the client's next transfer has to make a new one."""
        with self._lock:
            ends, self._open = self._open, []
            self._live = []
        for end in ends:
            try:
                end.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            end.close()

    def close(self):
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()
        for end in self._open:
            try:
                end.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            end.close()
        self._open = []

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.close()
        self.thread.join(5)


class FakeIcap:
    """
    An ICAP server (RFC 3507), enough for SecureTransport's scan: OPTIONS, then
    REQMOD or RESPMOD with an Encapsulated header and a chunked body, with or
    without a preview. A file whose bytes contain `marker` is blocked with a
    403 response; anything else is let through with 204 No Content.

    requests holds one dict per scan: method, icap_headers (a dict), http_head
    (the encapsulated HTTP header, as text), body (the file's bytes so far, up
    to the whole file) and blocked. options holds the OPTIONS requests seen.
    """
    MARKER = b"EICAR-ICAP-TEST"

    def __init__(self, port=0, marker=None, preview=1024):
        self.marker = marker if marker is not None else self.MARKER
        self.preview = preview
        self.requests, self.options, self.raw = [], [], []
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("0.0.0.0", port))
        self.sock.listen()
        self.port = self.sock.getsockname()[1]
        self.thread = threading.Thread(target=self._accept, daemon=True)

    def _accept(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    @staticmethod
    def _read_until(conn, buf, token):
        while token not in buf:
            data = conn.recv(65536)
            if not data:
                return None, buf
            buf += data
        head, _, rest = buf.partition(token)
        return head, rest

    @staticmethod
    def _read_exact(conn, buf, size):
        while len(buf) < size:
            data = conn.recv(65536)
            if not data:
                break
            buf += data
        return buf[:size], buf[size:]

    def _read_chunks(self, conn, buf):
        """The chunked body: (bytes, whether it ended with ieof, the rest of the buffer)."""
        body, ieof = b"", False
        while True:
            line, buf = self._read_until(conn, buf, b"\r\n")
            if line is None:
                return body, ieof, buf
            size_text = line.split(b";")[0].strip()
            size = int(size_text or b"0", 16)
            ieof = b"ieof" in line
            if size == 0:
                _, buf = self._read_until(conn, buf, b"\r\n") if not buf.startswith(b"\r\n") else (None, buf[2:])
                return body, ieof, buf
            chunk, buf = self._read_exact(conn, buf, size)
            body += chunk
            _, buf = self._read_exact(conn, buf, 2)

    def _serve(self, conn):
        conn.settimeout(120)
        buf = b""
        try:
            while True:
                head, buf = self._read_until(conn, buf, b"\r\n\r\n")
                if head is None:
                    return
                lines = head.decode("latin-1").split("\r\n")
                self.raw.append(head)
                method = lines[0].split(" ")[0]
                headers = {k.strip().lower(): v.strip() for k, _, v in (l.partition(":") for l in lines[1:] if ":" in l)}
                if method == "OPTIONS":
                    self.options.append({"line": lines[0], "icap_headers": headers})
                    conn.sendall(("ICAP/1.0 200 OK\r\nMethods: REQMOD, RESPMOD\r\nService: FakeIcap\r\nISTag: \"fake-icap-1\"\r\n"
                                  "Max-Connections: 20\r\nOptions-TTL: 60\r\nAllow: 204\r\nPreview: %d\r\n"
                                  "Transfer-Complete: *\r\nEncapsulated: null-body=0\r\n\r\n" % self.preview).encode())
                    continue
                offsets = {}
                for part in headers.get("encapsulated", "").split(","):
                    key, _, value = part.strip().partition("=")
                    if value.isdigit():
                        offsets[key] = int(value)
                http_len = (offsets.get("req-body") or offsets.get("res-body") or offsets.get("null-body") or 0)
                http_head, buf = self._read_exact(conn, buf, http_len)
                body, ieof = b"", True
                if "req-body" in offsets or "res-body" in offsets:
                    body, ieof, buf = self._read_chunks(conn, buf)
                    if not ieof and "preview" in headers:
                        blocked_early = self.marker in body
                        if not blocked_early:
                            conn.sendall(b"ICAP/1.0 100 Continue\r\n\r\n")
                            more, _, buf = self._read_chunks(conn, buf)
                            body += more
                blocked = self.marker in body
                self.requests.append({"method": method, "icap_headers": headers, "http_head": http_head.decode("latin-1"),
                                      "body": body, "blocked": blocked})
                if blocked:
                    page = b"<html><body>Blocked by FakeIcap</body></html>"
                    http = b"HTTP/1.1 403 Forbidden\r\nContent-Type: text/html\r\nContent-Length: %d\r\n\r\n" % len(page)
                    conn.sendall(b"ICAP/1.0 200 OK\r\nISTag: \"fake-icap-1\"\r\nEncapsulated: res-hdr=0, res-body=%d\r\n\r\n" % len(http)
                                 + http + (b"%x\r\n" % len(page)) + page + b"\r\n0\r\n\r\n")
                else:
                    conn.sendall(b"ICAP/1.0 204 No Content\r\nISTag: \"fake-icap-1\"\r\nEncapsulated: null-body=0\r\n\r\n")
        except (OSError, ValueError):
            return
        finally:
            conn.close()

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()
        self.thread.join(5)


if __name__ == "__main__":
    kinds = {"vault": FakeVault, "token": FakeToken, "s3": FakeS3, "sink": TcpSink, "junk": JunkServer, "icap": FakeIcap}  # SlowProxy needs a target: use it from code
    if len(sys.argv) < 2 or sys.argv[1] not in kinds:
        sys.exit("usage: dummy_servers.py vault|token|s3|sink|junk|icap [PORT]")
    with kinds[sys.argv[1]](int(sys.argv[2]) if len(sys.argv) > 2 else 0) as dummy:
        print("%s listening on port %d; Ctrl-C to stop" % (sys.argv[1], dummy.port), flush=True)
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            pass
