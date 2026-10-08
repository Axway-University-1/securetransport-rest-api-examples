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
import urllib.parse
from multiprocessing import Value

PYTHON3_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "..", "..", "Admin", "API 2.0", "python", "python3")
UTILS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "..", "Admin", "API 2.0", "python", "utils")


# --------------------------------------------------------------------------
# A stand-in for the requests module
# --------------------------------------------------------------------------
# The examples import requests at the top of the file, so `import requests` has to
# find a stand-in while one is being loaded. fake_requests/ is the package that also
# stands in when an example is run as a whole (run_example.py), with the same
# exception classes as the real library: ConnectionError, Timeout and HTTPError are
# three different things there, and a test that raises one must not be caught as
# another.
FAKE_REQUESTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fake_requests")


def _install_fake_requests():
    for name in [n for n in sys.modules if n == "requests" or n.startswith("requests.")]:
        del sys.modules[name]
    sys.path.insert(0, FAKE_REQUESTS_DIR)
    try:
        import requests as fake
        import requests.packages.urllib3.exceptions  # noqa: F401
    finally:
        sys.path.remove(FAKE_REQUESTS_DIR)
    return fake


requests = _install_fake_requests()
_loaded_fake_modules = {n: m for n, m in sys.modules.items() if n == "requests" or n.startswith("requests.")}


class Response:
    def __init__(self, status_code=200, body=None, headers=None):
        self.status_code = status_code
        self._body = body if body is not None else {}
        self.headers = headers or {}
        self.text = json.dumps(self._body)
        self.content = self.text.encode()

    def json(self):
        return self._body

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.exceptions.HTTPError("%s Error" % self.status_code)


class FakeSession:
    """
    Serves collections with the paging shape ST uses, and records every write.

    pages maps a collection name to a list of objects:

        FakeSession({"routes": [{"id": "r1", ...}], "subscriptions": [...]})

    After a run, `writes` holds (verb, url, body) for each PATCH, PUT and POST,
    so a test can assert on exactly what would have been sent.

    totals maps a path that answers with a count, such as "logs/transfers", to
    a function of the decoded query parameters that returns the count:

        FakeSession(totals={"logs/transfers": lambda params: 7})

    The answer carries it as resultSet.totalCount, with returnCount capped by
    limit as the real endpoint does, so reading the wrong one shows.
    """

    def __init__(self, pages=None, login_ok=True, totals=None):
        self.pages = pages or {}
        self.writes = []
        self.reads = []
        self.login_ok = login_ok
        self.totals = totals or {}
        self.cert = None

    # -- helpers ----------------------------------------------------------
    def _split(self, url):
        tail = url.split("/api/v2.0/", 1)[1]
        path, _, query = tail.partition("?")
        params = dict(kv.split("=", 1) for kv in query.split("&") if "=" in kv)
        params = {k: urllib.parse.unquote_plus(v) for k, v in params.items()}
        return path, params

    def _total(self, path, params):
        total = self.totals[path](params)
        limit = int(params.get("limit", 200))
        return Response(200, {"resultSet": {"returnCount": min(total, limit),
                                            "totalCount": total},
                              "result": []})

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
        if path in self.totals:
            return self._total(path, params)
        if "/" in path:                     # a single object by id
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
        "numFailed": Value("i", 0),
        "apiCounter": Value("i", 0),
        "apiCount": Value("i", 0),
        "stUrl": "https://st.example.com:8444/api/v2.0/",
        "referer": "THIS_IS_A_RANDOM_TEXT",
        "stTimeout": 10,
        "stVerify": False,
        "logFile": os.devnull,
        "pollSeconds": 0,
        "dryRun": False,
    }
    namespace.update(overrides)
    # `import requests` at the top of an example finds the stand-in, and goes back
    # to normal afterwards
    saved = {n: m for n, m in sys.modules.items() if n == "requests" or n.startswith("requests.")}
    for name in saved:
        del sys.modules[name]
    sys.modules.update({n: m for n, m in _loaded_fake_modules.items()})
    try:
        exec(compile(source, script_name, "exec"), namespace)
    finally:
        for name in [n for n in sys.modules if n == "requests" or n.startswith("requests.")]:
            del sys.modules[name]
        sys.modules.update(saved)
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
