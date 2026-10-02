#!/usr/bin/env python3
"""
A fake SecureTransport, for testing the python examples offline.

The examples import `requests` and talk to a live server. This module stands in
for both, so a test can run the real functions out of an example and check what
they would have done:

    import fake_st
    ns = fake_st.load("stUpdateAllRoutes.py", emailToRemove="old@example.com")
    session = fake_st.FakeSession({"routes": [ ... ]})
    ns["stProcessSimpleRoutes"](session, "csrf-token")
    print(session.writes)        # every PATCH and PUT that would have been sent

Nothing here touches the network, and no credentials are needed.
"""
import datetime
import json
import os
import sys
import types
from multiprocessing import Value

PYTHON3_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "..", "..", "Admin", "API 2.0", "python", "python3")
UTILS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "..", "Admin", "API 2.0", "python", "utils")


# --------------------------------------------------------------------------
# A stand-in for the requests module
# --------------------------------------------------------------------------
class _StubError(Exception):
    pass


requests = types.ModuleType("requests")
requests.ConnectionError = _StubError
requests.exceptions = types.SimpleNamespace(HTTPError=_StubError,
                                            Timeout=_StubError,
                                            RequestException=_StubError)
requests.packages = types.SimpleNamespace(
    urllib3=types.SimpleNamespace(
        exceptions=types.SimpleNamespace(InsecureRequestWarning=Warning),
        disable_warnings=lambda *a, **k: None))


class Response:
    def __init__(self, status_code=200, body=None, headers=None):
        self.status_code = status_code
        self._body = body if body is not None else {}
        self.headers = headers or {}
        self.text = json.dumps(self._body)
        self.content = self.text.encode()

    def json(self):
        return self._body


class FakeSession:
    """
    Serves collections with the paging shape ST uses, and records every write.

    pages maps a collection name to a list of objects:

        FakeSession({"routes": [{"id": "r1", ...}], "subscriptions": [...]})

    After a run, `writes` holds (verb, url, body) for each PATCH, PUT and POST,
    so a test can assert on exactly what would have been sent.
    """

    def __init__(self, pages=None, login_ok=True):
        self.pages = pages or {}
        self.writes = []
        self.reads = []
        self.login_ok = login_ok

    # -- helpers ----------------------------------------------------------
    def _split(self, url):
        tail = url.split("/api/v2.0/", 1)[1]
        path, _, query = tail.partition("?")
        params = dict(kv.split("=", 1) for kv in query.split("&") if "=" in kv)
        return path, params

    def _collection_page(self, collection, params):
        offset = int(params.get("offset", 0))
        limit = int(params.get("limit", 200))
        items = self.pages.get(collection, [])[offset:offset + limit]
        return Response(200, {"resultSet": {"returnCount": len(items)},
                              "result": items})

    # -- the verbs the examples use ---------------------------------------
    def get(self, url, **kwargs):
        self.reads.append(url)
        path, params = self._split(url)
        if "/" in path:                       # a single object by id
            collection, ident = path.split("/", 1)
            for item in self.pages.get(collection, []):
                if str(item.get("id")) == ident:
                    return Response(200, item)
            return Response(404, {"message": "not found"})
        return self._collection_page(path, params)

    def post(self, url, **kwargs):
        if url.endswith("/myself"):
            if not self.login_ok:
                return Response(401, {"message": "Unauthorized"})
            return Response(200, {"message": "Logged in"},
                            {"csrfToken": "fake-csrf-token"})
        self.writes.append(("POST", url, kwargs.get("json")))
        return Response(201, {}, {"Location": url + "/new-object-id"})

    def delete(self, url, **kwargs):
        if url.endswith("/myself"):
            return Response(200, {"message": "Logged out"})
        self.writes.append(("DELETE", url, None))
        return Response(204, {})

    def patch(self, url, **kwargs):
        self.writes.append(("PATCH", url, kwargs.get("json")))
        return Response(204, {})

    def put(self, url, **kwargs):
        self.writes.append(("PUT", url, kwargs.get("json")))
        return Response(204, {})


# --------------------------------------------------------------------------
# Loading an example's functions without running its main block
# --------------------------------------------------------------------------
def load(script_name, directory=None, **overrides):
    """
    Execute the function definitions of an example and return its namespace.

    Everything above `if __name__ == "__main__":` is executed, so the functions
    are defined but nothing runs. The globals the functions expect are injected,
    and `overrides` sets the configuration values a test wants.
    """
    base = directory or PYTHON3_DIR
    path = os.path.join(base, script_name)
    source = open(path).read().split('if __name__ == "__main__":')[0]

    namespace = {
        "requests": requests,
        "datetime": datetime,
        "sys": sys,
        "json": json,
        "os": os,
        "numAPIs": Value("i", 0),
        "apiCounter": Value("i", 0),
        "stUrl": "https://st.example.com:8444/api/v2.0/",
        "referer": "THIS_IS_A_RANDOM_TEXT",
        "stTimeout": 10,
        "dryRun": False,
    }
    namespace.update(overrides)
    exec(compile(source, script_name, "exec"), namespace)
    return namespace


# --------------------------------------------------------------------------
# A very small assertion helper, so the checks stay readable
# --------------------------------------------------------------------------
class Checker:
    def __init__(self, title):
        self.passed = 0
        self.failed = 0
        print("=== " + title + " ===")

    def check(self, label, condition, detail=""):
        if condition:
            self.passed += 1
            print("  PASS  " + label)
        else:
            self.failed += 1
            print("  FAIL  " + label + (("  got: " + str(detail)) if detail else ""))
        return condition

    def summary(self):
        print("  %d passed, %d failed" % (self.passed, self.failed))
        return self.failed == 0
