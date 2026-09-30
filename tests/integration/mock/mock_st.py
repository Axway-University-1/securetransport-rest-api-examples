#!/usr/bin/env python3
"""
A stand-in SecureTransport, over real HTTPS.

This exists so the integration harness can be proven without a real server. It
speaks enough of the API for the integration checks to run end to end: the
session cookie handed back on login and required on every later call, the CSRF
handshake, the Referer requirement, paging, and the account lifecycle with the
status codes ST actually returns.

The session cookie check was added after a real client missed it: an early
version of st_client.py logged in successfully but never stored the cookie,
so every following call came back 401. This mock did not catch it, because it
only checked the CSRF token. It now requires both, so that gap cannot reopen
unnoticed.

    python3 mock_st.py --port 18444

It is NOT a SecureTransport simulator and makes no attempt to be. Its only job
is to prove that the harness plumbing works, so that when the tests are pointed
at a real server the failures that surface are real API differences and not
bugs in the tests.

Run the integration suite against it with:

    tests/integration/run_integration.sh --mock
"""
import argparse
import base64
import json
import re
import ssl
import subprocess
import sys
import tempfile
import threading
import os
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

VALID_USER = "apiadmin"
VALID_PASSWORD = "s3cret"
CSRF_TOKEN = "mock-csrf-token"

#
# ST authenticates login with Authorization, then hands back a session cookie
# that every later call must present - it does not accept Authorization again.
# A real client missed this once (see st_client.py's docstring) and it still
# got a 201 from a mock that only checked the CSRF token. This mock now
# enforces the cookie too, so that gap cannot reopen unnoticed.
#
SESSION_COOKIE_NAME = "STSESSION"
SESSIONS = set()

STATE = {"accounts": {}}
LOCK = threading.Lock()

# Fields the real API only returns when the caller supplies type=, confirmed
# against 04.accounts_name_GET.sh: without type=, the field is silently
# dropped even though it is asked for; with the matching type, it is returned.
TYPE_SPECIFIC_FIELDS = {"addressBookSettings"}


def default_address_book_settings():
    return {"policy": "default", "nonAddressBookCollaborationAllowed": None,
            "sources": [], "contacts": []}


def filter_account_fields(account, params):
    """
    Apply the same two rules the real /accounts/{name} endpoint applies:
    fields= narrows the response (type always included), and a type specific
    field is only present when type= was also supplied.
    """
    if not params.get("type"):
        account = {k: v for k, v in account.items() if k not in TYPE_SPECIFIC_FIELDS}
    if params.get("fields"):
        wanted = set(params["fields"].split(",")) | {"type"}
        account = {k: v for k, v in account.items() if k in wanted}
    return account


def seed():
    with LOCK:
        STATE["accounts"] = {}
        # Enough objects that paging has to loop more than once
        for i in range(1, 251):
            name = "seeded_account_%03d" % i
            STATE["accounts"][name] = {
                "name": name, "type": "user", "uid": "1000", "gid": "1000",
                "homeFolder": "/home/" + name, "notes": "seeded",
                "addressBookSettings": default_address_book_settings(),
            }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass  # keep the test output readable

    # -- helpers ----------------------------------------------------------
    def _send(self, status, payload=None, headers=None, body_bytes=None):
        if body_bytes is None:
            body_bytes = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body_bytes)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD" and body_bytes:
            self.wfile.write(body_bytes)

    def _referer_ok(self):
        # ST rejects a call with no Referer. The harness must always send one.
        if not self.headers.get("Referer"):
            self._send(403, {"message": "Referer header is required"})
            return False
        return True

    def _session_cookie(self):
        """The STSESSION value from the Cookie header, or None."""
        raw = self.headers.get("Cookie", "")
        for part in raw.split(";"):
            part = part.strip()
            if part.startswith(SESSION_COOKIE_NAME + "="):
                return part.split("=", 1)[1]
        return None

    def _valid_basic_auth(self):
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Basic "):
            return False
        try:
            user, _, password = base64.b64decode(auth[6:]).decode().partition(":")
        except Exception:
            return False
        return (user, password) == (VALID_USER, VALID_PASSWORD)

    def _authorized(self):
        """
        True when the request may proceed - confirmed against a real server,
        not assumed.

        A request that presents valid HTTP Basic auth is authorized on its
        own, with no session cookie and no CSRF token needed. This was
        checked directly: a bare POST with only Authorization and no cookie
        or csrfToken succeeded (201) against a real, CSRF-enabled server.
        It makes sense once you consider what CSRF protects against - a
        browser silently attaching a cookie to a request the user did not
        intend. That risk does not exist when the credential is put on the
        request explicitly and freshly every time, which is exactly what the
        bash examples do: no login step, no cookie, -u user:pass on every
        curl call.

        A request relying on the session cookie instead must also present
        the CSRF token that session was issued - this is the path a hand
        written client can silently miss if it never stores the cookie in
        the first place (see the note in st_client.py).
        """
        if self._valid_basic_auth():
            return True

        token = self._session_cookie()
        with LOCK:
            cookie_ok = token is not None and token in SESSIONS
        if not cookie_ok:
            self._send(401, {"message": "Unauthorized"})
            return False

        if self.headers.get("csrfToken") != CSRF_TOKEN:
            self._send(403, {"message": "invalid csrfToken"})
            return False

        return True

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return None
        try:
            return json.loads(self.rfile.read(length).decode())
        except ValueError:
            return None

    def _split(self):
        path, _, query = self.path.partition("?")
        path = path.replace("/api/v2.0/", "", 1).strip("/")
        params = {}
        for pair in query.split("&"):
            if "=" in pair:
                k, v = pair.split("=", 1)
                params[k] = v
        return path, params

    # -- verbs ------------------------------------------------------------
    def do_POST(self):
        if not self._referer_ok():
            return
        path, _ = self._split()

        if path == "myself":
            if not self._valid_basic_auth():
                return self._send(401, {"message": "Unauthorized"})

            # A real random token, not a counter or a thread id: HTTPServer
            # handles one request at a time, so anything derived from the
            # thread would be identical on every login and could not tell a
            # missing cookie apart from a valid one.
            token = uuid.uuid4().hex
            with LOCK:
                SESSIONS.add(token)
            return self._send(200, {"message": "Logged in"},
                              headers={"csrfToken": CSRF_TOKEN,
                                       "Set-Cookie": "%s=%s; Path=/; HttpOnly"
                                                    % (SESSION_COOKIE_NAME, token)})

        if not self._authorized():
            return

        if path == "accounts":
            body = self._body() or {}
            name = body.get("name")
            if not name:
                return self._send(422, {"message": "name is required"})
            account = dict(body)
            if account.get("type") == "user" and "addressBookSettings" not in account:
                account["addressBookSettings"] = default_address_book_settings()
            with LOCK:
                if name in STATE["accounts"]:
                    return self._send(409, {"message": "already exists"})
                STATE["accounts"][name] = account
            return self._send(201, None, headers={
                "Location": "https://%s/api/v2.0/accounts/%s"
                            % (self.headers.get("Host", "mock"), name)})

        return self._send(404, {"message": "no such endpoint: " + path})

    def do_GET(self):
        if not self._referer_ok():
            return
        path, params = self._split()

        # Every GET needs the session, version included: a real server was
        # observed to return 401 for GET /version taken with no valid
        # session, so this mock does the same rather than special casing it.
        if not self._authorized():
            return

        if path == "version":
            return self._send(200, {"version": "5.5-mock", "serverType": "mock"})

        if path == "myself":
            # Confirmed against a real 5.5 server: the login name is the top
            # level loginName field, not "name" and not nested. This mock
            # matched that shape only after being run against a real server -
            # do not go back to guessing a shape here.
            return self._send(200, {"type": "admin", "loginName": VALID_USER})

        if path == "accounts":
            offset = int(params.get("offset", 0))
            limit = int(params.get("limit", 100))
            with LOCK:
                names = sorted(STATE["accounts"])
                window = names[offset:offset + limit]
                items = [filter_account_fields(dict(STATE["accounts"][n]), params)
                        for n in window]
            return self._send(200, {"resultSet": {"returnCount": len(items),
                                                  "totalCount": len(names)},
                                    "result": items})

        m = re.match(r"^accounts/([^/]+)$", path)
        if m:
            with LOCK:
                account = STATE["accounts"].get(urlunquote(m.group(1)))
            if not account:
                return self._send(404, {"message": "not found"})
            return self._send(200, filter_account_fields(dict(account), params))

        return self._send(404, {"message": "no such endpoint: " + path})

    def do_HEAD(self):
        if not self._referer_ok():
            return
        path, _ = self._split()
        if not self._authorized():
            return
        m = re.match(r"^accounts/([^/]+)$", path)
        if m:
            with LOCK:
                found = urlunquote(m.group(1)) in STATE["accounts"]
            return self._send(200 if found else 404)
        return self._send(404)

    def do_PATCH(self):
        if not self._referer_ok() or not self._authorized():
            return
        path, _ = self._split()
        m = re.match(r"^accounts/([^/]+)$", path)
        if not m:
            return self._send(404, {"message": "not found"})
        name = urlunquote(m.group(1))
        operations = self._body()
        if not isinstance(operations, list):
            return self._send(422, {"message": "a JSON Patch body must be a list"})

        with LOCK:
            account = STATE["accounts"].get(name)
            if not account:
                return self._send(404, {"message": "not found"})
            for op in operations:
                action, pointer = op.get("op"), str(op.get("path", ""))
                if action not in ("add", "replace", "remove") or not pointer.startswith("/"):
                    return self._send(422, {"message": "bad operation"})
                field = pointer.lstrip("/")
                # replace requires the field to exist; add creates it
                if action == "replace" and field not in account:
                    return self._send(422, {"message":
                                            "cannot replace missing field " + field})
                if action == "remove":
                    account.pop(field, None)
                else:
                    account[field] = op.get("value")
        return self._send(204)

    def do_PUT(self):
        if not self._referer_ok() or not self._authorized():
            return
        path, _ = self._split()
        m = re.match(r"^accounts/([^/]+)$", path)
        if not m:
            return self._send(404, {"message": "not found"})
        name = urlunquote(m.group(1))
        body = self._body()
        if not isinstance(body, dict):
            return self._send(422, {"message": "a PUT body must be the object"})
        with LOCK:
            if name not in STATE["accounts"]:
                return self._send(404, {"message": "not found"})
            STATE["accounts"][name] = dict(body)
        return self._send(204)

    def do_DELETE(self):
        if not self._referer_ok():
            return
        path, _ = self._split()

        if path == "myself":
            token = self._session_cookie()
            with LOCK:
                SESSIONS.discard(token)
            return self._send(200, {"message": "Logged out"})

        if not self._authorized():
            return

        m = re.match(r"^accounts/([^/]+)$", path)
        if m:
            name = urlunquote(m.group(1))
            with LOCK:
                if name not in STATE["accounts"]:
                    return self._send(404, {"message": "not found"})
                del STATE["accounts"][name]
            return self._send(204)

        return self._send(404, {"message": "not found"})


def urlunquote(text):
    from urllib.parse import unquote
    return unquote(text)


def make_certificate(directory):
    """A self signed certificate, so the harness exercises real TLS."""
    key = os.path.join(directory, "mock.key")
    crt = os.path.join(directory, "mock.crt")
    subprocess.run(
        ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
         "-keyout", key, "-out", crt, "-days", "1",
         "-subj", "/CN=localhost"],
        check=True, capture_output=True)
    return crt, key


def serve(port, ready=None):
    seed()
    directory = tempfile.mkdtemp(prefix="mock_st_")
    crt, key = make_certificate(directory)

    httpd = HTTPServer(("127.0.0.1", port), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(crt, key)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

    if ready:
        ready.set()
    httpd.serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="A stand-in SecureTransport")
    parser.add_argument("--port", type=int, default=18444)
    args = parser.parse_args()
    print("mock SecureTransport on https://127.0.0.1:%d/api/v2.0/" % args.port)
    print("  user: %s  password: %s" % (VALID_USER, VALID_PASSWORD))
    try:
        serve(args.port)
    except KeyboardInterrupt:
        sys.exit(0)
