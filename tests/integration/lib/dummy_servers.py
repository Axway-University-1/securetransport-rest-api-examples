#!/usr/bin/env python3
"""
Throwaway stand-ins for the outside systems a SecureTransport server talks to,
so the integration checks can exercise a configuration end to end without a
real HashiCorp Vault, S3 bucket or Axway Sentinel:

- FakeVault  answers an AppRole login and KV version 2 secret reads, the two
             calls an ST external store makes.
- FakeS3     answers path-style S3 requests with any credentials, keeping
             objects in memory - enough for an S3 storage profile's test.
- TcpSink    accepts connections and keeps what it receives, for Sentinel.

Each runs in a background thread on a port the system picks, listening on
every interface, and records the requests it saw. The ST server must be able
to reach this machine: set st_callback_host in integration.conf to this
machine's address as the server sees it.

    with dummy_servers.FakeVault() as vault:
        url = "http://%s:%d" % (callback_host, vault.port)
        ...
        assert any(r["path"].endswith("/approle/login") for r in vault.requests)

Run on its own to keep one up by hand:  python3 dummy_servers.py vault|s3|sink [PORT]
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
        self.sock.close()


if __name__ == "__main__":
    kinds = {"vault": FakeVault, "s3": FakeS3, "sink": TcpSink}
    if len(sys.argv) < 2 or sys.argv[1] not in kinds:
        sys.exit("usage: dummy_servers.py vault|s3|sink [PORT]")
    with kinds[sys.argv[1]](int(sys.argv[2]) if len(sys.argv) > 2 else 0) as dummy:
        print("%s listening on port %d; Ctrl-C to stop" % (sys.argv[1], dummy.port), flush=True)
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            pass
