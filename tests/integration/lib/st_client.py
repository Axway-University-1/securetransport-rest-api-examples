#!/usr/bin/env python3
"""
A small SecureTransport client for the integration tests.

Standard library only, so the integration tests run on any machine without a
pip install. The examples themselves use `requests`; this is test
infrastructure, and keeping it dependency free means there is no reason not to
run it.

It implements the parts of the protocol that are easy to get wrong:

  - the Referer header, which ST requires and which must not change during a
    session
  - the session cookie ST sets on a successful login. Authorization is only
    sent on that first call; every later call proves the session with the
    cookie, not with Authorization again. requests.Session() does this
    invisibly, which is exactly why it is easy to leave out of a client
    written by hand - it did, once, here: an early version of this file had
    no cookie jar, so login succeeded and every following call still came
    back 401.
  - the CSRF token handshake, which applies from the 20230525 release
  - paging with offset, limit and resultSet.returnCount

See .claude/skills/st-api-gotchas/SKILL.md for why each of those matters.
"""
import base64
import datetime
import http.cookiejar
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


class STError(Exception):
    def __init__(self, message, status=None, body=None):
        super().__init__(message)
        self.status = status
        self.body = body


class Response:
    def __init__(self, status, headers, body_bytes):
        self.status = status
        self.headers = headers
        self.body = body_bytes

    def json(self):
        if not self.body:
            return None
        try:
            return json.loads(self.body.decode("utf-8"))
        except ValueError:
            return None

    @property
    def text(self):
        return self.body.decode("utf-8", "replace") if self.body else ""


class STClient:
    """
    A logged in session against one SecureTransport server.

    Use it as a context manager so that the session is always closed:

        with STClient(server, port, user, password) as st:
            st.get("accounts", params={"limit": 5})
    """

    def __init__(self, server, port, user, password,
                 referer="THIS_IS_A_RANDOM_TEXT", timeout=30, verify_tls=False):
        self.base = "https://%s:%s/api/v2.0/" % (server, port)
        self.referer = referer
        self.timeout = timeout
        self.calls = 0
        self._csrf = None

        self._auth = base64.b64encode(
            ("%s:%s" % (user, password)).encode()).decode()

        if verify_tls:
            self._ssl = ssl.create_default_context()
        else:
            # These are lab systems with self signed certificates, exactly as
            # the examples assume with curl -k and verify=False.
            self._ssl = ssl.create_default_context()
            self._ssl.check_hostname = False
            self._ssl.verify_mode = ssl.CERT_NONE

        #
        # ST authenticates the login call itself with the Authorization
        # header, then hands back a session cookie. Every later call proves
        # the session with that cookie, not with Authorization again - the
        # python examples get this for free from requests.Session(), which
        # is exactly what this cookie jar replicates for urllib.
        #
        self._cookies = http.cookiejar.CookieJar()
        self._opener = urllib.request.build_opener(
            urllib.request.HTTPSHandler(context=self._ssl),
            urllib.request.HTTPCookieProcessor(self._cookies))

    # -- plumbing ---------------------------------------------------------
    def _request(self, method, path, params=None, body=None, extra_headers=None):
        url = self.base + path.lstrip("/")
        if params:
            url += "?" + urllib.parse.urlencode(params)

        headers = {"Referer": self.referer, "Accept": "application/json"}
        if self._csrf:
            headers["csrfToken"] = self._csrf
        if extra_headers:
            headers.update(extra_headers)

        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"

        request = urllib.request.Request(url, data=data, headers=headers,
                                         method=method)
        self.calls += 1
        try:
            with self._opener.open(request, timeout=self.timeout) as handle:
                return Response(handle.status, dict(handle.headers), handle.read())
        except urllib.error.HTTPError as e:
            return Response(e.code, dict(e.headers), e.read())
        except urllib.error.URLError as e:
            raise STError("cannot reach %s: %s" % (url, e.reason)) from e
        except OSError as e:
            # A timeout or reset after the connection was made, such as while
            # the server restarts its daemons: urllib raises these as they are,
            # not as URLError. As an STError, every check handles them alike.
            raise STError("no answer from %s: %s" % (url, e)) from e

    # -- session ----------------------------------------------------------
    def login(self):
        response = self._request(
            "POST", "myself",
            extra_headers={"Authorization": "Basic " + self._auth})

        if response.status == 401:
            raise STError("login refused: check st_user and st_password",
                          response.status, response.text)
        if response.status != 200:
            raise STError("login failed", response.status, response.text)

        # Present from the 20230525 release. Absent on older servers, which is
        # not an error: the later calls simply do not send the header.
        self._csrf = response.headers.get("csrfToken")
        return self._csrf

    def logout(self):
        if self._csrf is None and not self.calls:
            return
        self._request("DELETE", "myself")
        self._csrf = None

    def __enter__(self):
        self.login()
        return self

    def __exit__(self, *exc):
        try:
            self.logout()
        except STError:
            pass
        return False

    # -- verbs ------------------------------------------------------------
    def get(self, path, params=None):
        return self._request("GET", path, params=params)

    def head(self, path, params=None):
        return self._request("HEAD", path, params=params)

    def post(self, path, body, params=None):
        return self._request("POST", path, params=params, body=body)

    def put(self, path, body, params=None):
        return self._request("PUT", path, params=params, body=body)

    def patch(self, path, body, params=None):
        return self._request("PATCH", path, params=params, body=body)

    def delete(self, path, params=None):
        return self._request("DELETE", path, params=params)

    # -- helpers ----------------------------------------------------------
    def exists(self, path):
        """True when the object is there. Uses HEAD, the cheap check."""
        return self.head(path).status == 200

    def page(self, collection, params=None, page_size=200, max_objects=None):
        """
        Walk a collection and yield every object.

        Stops when a page comes back smaller than the page size, which is the
        paging contract the examples use.
        """
        offset = 0
        seen = 0
        while True:
            query = dict(params or {})
            query.update({"offset": offset, "limit": page_size})
            response = self.get(collection, params=query)
            if response.status != 200:
                raise STError("GET %s failed" % collection,
                              response.status, response.text)

            payload = response.json() or {}
            results = payload.get("result", [])
            for item in results:
                yield item
                seen += 1
                if max_objects and seen >= max_objects:
                    return

            returned = payload.get("resultSet", {}).get("returnCount", len(results))
            if returned < page_size:
                return
            offset += page_size


# --------------------------------------------------------------------------
# Configuration, read from tests/local/integration.conf which git ignores
# --------------------------------------------------------------------------
def config_path():
    """tests/local/integration.conf, or the file named by ST_INTEGRATION_CONF (the mock run uses it)."""
    if os.environ.get("ST_INTEGRATION_CONF"):
        return os.path.abspath(os.environ["ST_INTEGRATION_CONF"])
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", "..", "local", "integration.conf"))


def load_config():
    """
    Returns the parsed config, or None when there is none.

    None means "no server was configured", which the runner treats as a skip
    rather than a failure, so the offline suite stays green on a clean clone.
    """
    path = config_path()
    if not os.path.exists(path):
        return None

    config = {}
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            config[key.strip()] = value.strip().strip('"')
    return config


def client_from_config(config):
    missing = [k for k in ("st_server", "st_port", "st_user", "st_password")
               if not config.get(k)]
    if missing:
        raise STError("integration.conf is missing: " + ", ".join(missing))

    return STClient(config["st_server"], config["st_port"],
                    config["st_user"], config["st_password"],
                    referer=config.get("st_referer", "THIS_IS_A_RANDOM_TEXT"),
                    timeout=int(config.get("st_timeout", "30")),
                    verify_tls=config.get("st_verify_tls", "no").lower() in ("yes", "true", "1"))


# --------------------------------------------------------------------------
# A very small test reporter, shared by the integration checks
# --------------------------------------------------------------------------
class Checker:
    def __init__(self, title):
        self.passed = 0
        self.failed = 0
        print("=== %s ===" % title)

    def check(self, label, condition, detail=""):
        if condition:
            self.passed += 1
            print("  PASS  " + label)
        else:
            self.failed += 1
            print("  FAIL  " + label + (("  got: " + str(detail)) if detail else ""))
        return bool(condition)

    def info(self, message):
        print("  ..    " + message)

    def done(self):
        print("  %d passed, %d failed" % (self.passed, self.failed))
        if self.passed == 0 and self.failed == 0:
            # A check that bailed out (the mock cannot do this one, an object it needs
            # is missing) asserted nothing: that is a skip, not a pass
            print("  SKIP  no assertion was made")
        return 0 if self.failed == 0 else 1


def connect(config, checker):
    """
    Log in, or report a clean failure and stop.

    An unreachable server is the first thing anyone hits, so it must read as a
    one line failure and not a stack trace.
    """
    client = client_from_config(config)
    try:
        client.login()
    except STError as e:
        checker.check("connect to the server", False, e)
        sys.exit(checker.done())
    return client


def find_value(obj, target, path=""):
    """
    Search a parsed JSON response for a leaf value matching target, and return
    the dotted path where it was found, or None.

    Field names have already been observed to drift between releases and
    between object types (see .claude/skills/st-api-gotchas/SKILL.md) - the
    admin identity object is not guaranteed to shape like an account object.
    Use this instead of asserting a specific field name you have not actually
    confirmed on a real server.
    """
    if target is None:
        return None
    needle = str(target).lower()

    if isinstance(obj, dict):
        for key, value in obj.items():
            found = find_value(value, target, path + "." + key)
            if found:
                return found
        return None

    if isinstance(obj, list):
        for i, value in enumerate(obj):
            found = find_value(value, target, path + "[%d]" % i)
            if found:
                return found
        return None

    if obj is not None and str(obj).lower() == needle:
        return path or "."

    return None


class EndUserClient:
    """
    A client for the small EndUser API (login and file transfer), as distinct
    from STClient, which is the admin API.

    Confirmed against the real EndUser bash examples: login sends
    Authorization once and gets a session cookie back, exactly like the admin
    API - but there is no CSRF token anywhere in this API, and no per-call
    Authorization either; every call after login relies on the cookie alone.

    A file is not returned as JSON: GET /files/{path} sends the raw bytes, and
    POST /files is a multipart upload. That is different enough from STClient
    that this is a separate class rather than a subclass.
    """

    def __init__(self, server, port, user, password, referer="THIS_IS_A_RANDOM_TEXT",
                timeout=30, verify_tls=False):
        self.base = "https://%s:%s/api/v2.0/" % (server, port)
        self.referer = referer
        self.timeout = timeout
        self.calls = 0
        self._auth = base64.b64encode(("%s:%s" % (user, password)).encode()).decode()

        self._ssl = ssl.create_default_context()
        if not verify_tls:
            self._ssl.check_hostname = False
            self._ssl.verify_mode = ssl.CERT_NONE

        self._cookies = http.cookiejar.CookieJar()
        self._opener = urllib.request.build_opener(
            urllib.request.HTTPSHandler(context=self._ssl),
            urllib.request.HTTPCookieProcessor(self._cookies))

    def _request(self, method, path, headers=None, data=None):
        url = self.base + path.lstrip("/")
        all_headers = {"Referer": self.referer, "Accept": "application/json"}
        all_headers.update(headers or {})
        request = urllib.request.Request(url, data=data, headers=all_headers, method=method)
        self.calls += 1
        try:
            with self._opener.open(request, timeout=self.timeout) as handle:
                return Response(handle.status, dict(handle.headers), handle.read())
        except urllib.error.HTTPError as e:
            return Response(e.code, dict(e.headers), e.read())
        except urllib.error.URLError as e:
            raise STError("cannot reach %s: %s" % (url, e.reason)) from e
        except OSError as e:
            # A timeout or reset after the connection was made, such as while
            # the server restarts its daemons: urllib raises these as they are,
            # not as URLError. As an STError, every check handles them alike.
            raise STError("no answer from %s: %s" % (url, e)) from e

    def login(self):
        response = self._request("POST", "myself",
                                 headers={"Authorization": "Basic " + self._auth})
        if response.status != 200:
            raise STError("EndUser login failed", response.status, response.text)
        return response

    def logout(self):
        return self._request("DELETE", "myself")

    def list_files(self, params=None):
        path = "files"
        if params:
            path += "?" + urllib.parse.urlencode(params)
        return self._request("GET", path)

    def download(self, filepath):
        return self._request("GET", "files/" + filepath)

    def create_folder(self, folder):
        """
        POST /files/{folder}: the name goes in the URL, and the body only says it
        is a directory. A name in the body is answered with 409.
        """
        body = json.dumps({"isDirectory": True, "isRegularFile": False, "isSymbolicLink": False,
                           "isOther": False, "isShared": False}).encode()
        return self._request("POST", "files/" + urllib.parse.quote(folder.strip("/")),
                             headers={"Content-Type": "application/json"}, data=body)

    def list_folder(self, folder):
        """
        The names of the regular files in a folder of the home folder, or
        None when the folder cannot be read. GET /files/{folder} answers with
        {"files": [{"fileName": ..., "isRegularFile": ...}, ...]}.
        """
        response = self._request("GET", "files/" + urllib.parse.quote(folder.strip("/")))
        if response.status != 200:
            return None
        return [f.get("fileName") for f in (response.json() or {}).get("files", [])
                if f.get("isRegularFile")]

    def delete_file(self, filepath):
        """
        DELETE /files/{path}. Confirmed to work, though no shipped EndUser
        example demonstrates it - see .claude/skills/st-api-gotchas/SKILL.md.
        """
        return self._request("DELETE", "files/" + filepath)

    def upload(self, filepath, content, filename=None):
        """
        A minimal multipart/form-data body for one file - no external
        library, matching the standard library only rule for this harness.
        """
        boundary = "----STIntegrationBoundary"
        name = filename or os.path.basename(filepath)
        body = (
            ("--%s\r\n" % boundary).encode()
            + ('Content-Disposition: form-data; name="file"; filename="%s"\r\n\r\n' % name).encode()
            + content
            + ("\r\n--%s--\r\n" % boundary).encode()
        )
        headers = {"Content-Type": "multipart/form-data; boundary=" + boundary}
        return self._request("POST", "files", headers=headers, data=body)

    def __enter__(self):
        self.login()
        return self

    def __exit__(self, *exc):
        try:
            self.logout()
        except STError:
            pass
        return False


def is_mock(client):
    """
    True when client is talking to the bundled mock rather than a real server.

    The mock only ever implements /accounts and /myself. A check that needs
    another endpoint - /servers, /businessUnits, /sites, /configurations,
    /daemons - should call this after login and skip cleanly with an
    explanatory message rather than fail with a confusing 404, which is not a
    real regression, just a resource the mock does not model.
    """
    response = client.get("version")
    body = response.json() or {}
    return body.get("serverType") == "mock"


def release_at_least(version, release):
    """
    True when a version string from GET /version, such as "5.5-20260924", is
    the given release or later. A release is a product version and a build
    date; a newer product version counts as later whatever its date. An
    unreadable version is treated as older, so a feature check skips rather
    than fails.
    """
    def parse(text):
        match = re.search(r"(\d+(?:\.\d+)*)-(\d{8})", str(text or ""))
        if not match:
            return None
        return tuple(int(p) for p in match.group(1).split(".")), match.group(2)

    have, want = parse(version), parse(release)
    if not have or not want:
        return False
    if have[0] != want[0]:
        return have[0] > want[0]
    return have[1] >= want[1]


def server_release_at_least(client, release):
    """release_at_least() for the server client is connected to."""
    return release_at_least((client.get("version").json() or {}).get("version"), release)



def seconds_to_wait_for_midnight(now, margin=90):
    """
    How long to wait so that a check which compares days is not split by midnight:
    the check lists the days first, and the script it runs lists them again a moment
    later, and across midnight the two lists differ. Zero unless midnight is less
    than `margin` seconds away, when it is the time left plus a few seconds.
    """
    midnight = (now + datetime.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    left = (midnight - now).total_seconds()
    return left + 5 if left < margin else 0


def avoid_midnight(margin=90):
    """Wait out midnight, if it is closer than `margin` seconds, before a check that compares days."""
    wait = seconds_to_wait_for_midnight(datetime.datetime.now(), margin)
    if wait:
        print("  ..    midnight is close: waiting %d s for it to pass, so that no day changes during this check" % wait)
        time.sleep(wait)

def skip(reason):
    """Exit cleanly, so a missing server is a skip and not a failure."""
    print("  SKIP  " + reason)
    sys.exit(0)
