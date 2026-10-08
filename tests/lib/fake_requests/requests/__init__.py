"""
A stand-in for the requests library, for running the python examples offline.

tests/lib/fake_requests is put first on PYTHONPATH, so `import requests` in an
example finds this instead of the real library, and every call it makes goes to
a small in-memory SecureTransport (_server.py) instead of the network. The same
module is what a spawned worker process imports, so the multiprocessing
examples run for real.

A scenario file (FAKE_ST_SCENARIO, JSON) gives the objects the server holds and
how it should misbehave; FAKE_ST_LOG names the file that every call is
appended to, one JSON object per line. Nothing here touches the network.
"""
import json
import os

from . import exceptions
from .exceptions import (ConnectionError, ConnectTimeout, HTTPError,  # noqa: F401
                         ReadTimeout, RequestException, Timeout)
from . import packages  # noqa: F401
from . import _server


class Request:
    def __init__(self, *args, **kwargs):
        pass


class CaseInsensitiveDict(dict):
    def __init__(self, items=None):
        super().__init__()
        for k, v in (items or {}).items():
            self[k] = v

    def __setitem__(self, key, value):
        super().__setitem__(key.lower(), value)

    def __getitem__(self, key):
        return super().__getitem__(key.lower())

    def get(self, key, default=None):
        return super().get(key.lower(), default)

    def __contains__(self, key):
        return super().__contains__(key.lower())


class Response:
    def __init__(self, status_code=200, body=None, headers=None, raw=None):
        self.status_code = status_code
        self.headers = CaseInsensitiveDict(headers)
        if raw is not None:
            self.content = raw
            self.text = raw.decode("latin-1")
            self._body = None
        else:
            self._body = body if body is not None else {}
            self.text = json.dumps(self._body)
            self.content = self.text.encode()

    @property
    def ok(self):
        return self.status_code < 400

    def json(self):
        if self._body is None:
            raise ValueError("not json")
        return self._body

    def raise_for_status(self):
        if self.status_code >= 400:
            raise HTTPError("%s Error" % self.status_code)


class Session:
    def __init__(self):
        self.cert = None
        self.verify = True
        self.headers = {}
        self.cookies = {}
        self.auth = None
        self._st = _server.for_this_process()
        self._token = None
        self._referer = None
        self._logged_in = False

    def request(self, method, url, headers=None, params=None, json=None, data=None,
                files=None, verify=None, timeout=None, **kwargs):
        return self._st.handle(self, method.upper(), url, dict(headers or {}), params, json,
                               data, files, timeout, verify)

    def get(self, url, **kwargs):
        return self.request("GET", url, **kwargs)

    def head(self, url, **kwargs):
        return self.request("HEAD", url, **kwargs)

    def post(self, url, **kwargs):
        return self.request("POST", url, **kwargs)

    def put(self, url, **kwargs):
        return self.request("PUT", url, **kwargs)

    def patch(self, url, **kwargs):
        return self.request("PATCH", url, **kwargs)

    def delete(self, url, **kwargs):
        return self.request("DELETE", url, **kwargs)

    def close(self):
        pass
