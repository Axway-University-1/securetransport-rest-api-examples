"""
A small in-memory SecureTransport Admin API 2.0, behind the fake requests Session.

It enforces what the real server is documented to enforce, and which the lab is
lenient about, so an example that forgets it fails here:

  - every call carries a Referer, the same one the login used;
  - after the login every write (POST, PUT, PATCH, DELETE, the logout too) carries
    the csrfToken header the login answered with;
  - every call has a timeout.

A call that breaks one of these is answered 403 and recorded with a "violation".

The scenario (a JSON file named by FAKE_ST_SCENARIO) holds:

    collections   {"accounts": [ {...}, ... ], "routes": [...]}   what GET lists
    objects       {"transactionManager": {"status": "Running."}}   single objects
    totals        {"logs/transfers": 7}                            count answers
    fail          {"kind": "raise:ConnectionError" | "raise:Timeout" | "status:401" | "status:500",
                   "on": "all" | "login" | "after_login",          (default all)
                   "method": "DELETE", "path": "routes"}           (optional narrowing)
    stop_lag      how many reads of /servers still show a stopped daemon as active (default 0)
    service_lag   the same for a cluster service stopped through /clusterServices/operations
    csrf          false to behave like a server without CSRF (default true)
    ignore_filters  query parameters a list answer does not filter by, as accountType= on the lab

Every call is appended to FAKE_ST_LOG as one JSON line.
"""
import copy
import json
import os
import re
import urllib.parse
import uuid

from . import exceptions

API = "/api/v2.0/"
# fields the real server returns whether or not fields= asks for them, as confirmed on the lab
ALWAYS = {"servers": ["protocol"], "accounts": ["type"]}
DUPLICATES_OK = ("routes",)

_instance = None


def for_this_process():
    global _instance
    if _instance is None:
        _instance = FakeST()
    return _instance


class FakeST:
    def __init__(self):
        path = os.environ.get("FAKE_ST_SCENARIO")
        scenario = json.load(open(path)) if path else {}
        self.scenario = scenario
        self.collections = copy.deepcopy(scenario.get("collections", {}))
        self.objects = copy.deepcopy(scenario.get("objects", {}))
        self.totals = scenario.get("totals", {})
        self.fail = scenario.get("fail")
        self.stop_lag = int(scenario.get("stop_lag", 0))
        self.service_lag = int(scenario.get("service_lag", 0))
        self.csrf = scenario.get("csrf", True)
        self.ignored_filters = scenario.get("ignore_filters", [])
        self.log_path = os.environ.get("FAKE_ST_LOG")
        self.calls = 0

    # -- the log --------------------------------------------------------------
    def record(self, entry):
        if self.log_path:
            with open(self.log_path, "a") as f:
                f.write(json.dumps(entry) + "\n")

    # -- misbehaviour ---------------------------------------------------------
    def _failure(self, session, method, path, is_login):
        fail = self.fail
        if not fail:
            return None
        on = fail.get("on", "all")
        if on == "login" and not is_login:
            return None
        if on == "after_login" and (is_login or not session._logged_in):
            return None
        if fail.get("method") and fail["method"] != method:
            return None
        if fail.get("path") and fail["path"] not in path:
            return None
        return fail["kind"]

    def _response(self, status, body=None, headers=None, raw=None):
        from . import Response
        return Response(status, body, headers, raw)

    # -- the entry point ------------------------------------------------------
    def handle(self, session, method, url, headers, params, body, data, files, timeout, verify=None):
        self.calls += 1
        tail = url.split(API, 1)[1] if API in url else url
        path, _, query = tail.partition("?")
        qs = {k: urllib.parse.unquote_plus(v) for k, v in
              (kv.split("=", 1) for kv in query.split("&") if "=" in kv)}
        for k, v in (params or {}).items():
            qs[k] = str(v)
        is_login = method == "POST" and path == "myself"
        lower = {k.lower(): v for k, v in headers.items()}
        entry = {"method": method, "path": path, "query": qs, "url": url,
                 "has_csrf": "csrftoken" in lower, "verify": verify, "body": body, "files": sorted((files or {}).keys())}

        kind = self._failure(session, method, path, is_login)
        if kind and kind.startswith("raise:"):
            entry["raised"] = kind
            self.record(entry)
            raise getattr(exceptions, kind.split(":", 1)[1])("fake %s" % kind)
        if kind and kind.startswith("status:"):
            status = int(kind.split(":", 1)[1])
            entry["status"] = status
            self.record(entry)
            return self._response(status, {"message": "fake failure"})

        violation = None
        if timeout is None:
            violation = "no timeout on the call"
        if not lower.get("referer"):
            violation = "no Referer header"
        elif session._referer is not None and lower["referer"] != session._referer:
            violation = "a Referer different from the login's"
        if is_login:
            if "authorization" not in lower and not session.cert:
                violation = "login with neither Authorization nor a client certificate"
        elif method != "GET" and method != "HEAD" and self.csrf and session._logged_in:
            if lower.get("csrftoken") != session._token:
                violation = "a write with no valid csrfToken header"
        if violation:
            entry["violation"] = violation
            entry["status"] = 403
            self.record(entry)
            return self._response(403, {"message": violation})

        if is_login:
            session._referer = lower["referer"]
            session._logged_in = True
            session._token = "tok-" + uuid.uuid4().hex[:8] if self.csrf else None
            entry["status"] = 200
            self.record(entry)
            return self._response(200, {"message": "Logged in"},
                                  {"csrfToken": session._token} if session._token else {})
        if not session._logged_in:
            entry["status"] = 401
            self.record(entry)
            return self._response(401, {"message": "Authentication required"})

        response = self._route(session, method, path, qs, body, data, files, entry)
        entry["status"] = response.status_code
        self.record(entry)
        return response

    # -- routing --------------------------------------------------------------
    def _route(self, session, method, path, qs, body, data, files, entry):
        if path == "myself" and method == "DELETE":
            session._logged_in = False
            return self._response(200, {"message": "Logged out"})
        if path in self.totals and method == "GET":
            total = self.totals[path]
            return self._response(200, {"resultSet": {"returnCount": min(total, int(qs.get("limit", 200))),
                                                      "totalCount": total}, "result": []})
        if path in self.objects and method == "GET":
            return self._response(200, copy.deepcopy(self.objects[path]))
        if path in ("daemons/operations", "clusterServices/operations", "transactionManager/operations"):
            return self._operation(path, method, qs, entry)
        if path == "certificates" and method == "POST" and data is not None:
            return self._import_certificate(data)
        match = re.match(r"^certificates/([^/]+)/operations$", path)
        if match and method == "POST":
            return self._export_certificate(match.group(1), qs, files)
        if path == "clusterServices" and method == "GET":
            return self._cluster_service(qs)

        collection, _, ident = path.partition("/")
        if collection == "configurations":      # configurations/options is a list of its own
            collection, ident = path, ""
        items = self.collections.setdefault(collection, [])
        if method == "GET" and not ident:
            return self._list(collection, items, qs)
        found = self._find(items, ident) if ident else None
        if method in ("GET", "HEAD") and ident:
            if found is None:
                return self._response(404, {"message": "not found"})
            return self._response(200, found if method == "GET" else {})
        if method == "POST" and not ident:
            return self._create(collection, items, body)
        if found is None:
            return self._response(404, {"message": "not found"})
        if method == "DELETE":
            items.remove(found)
            return self._response(204, {})
        if method == "PUT":
            keep = found.get("id")
            found.clear()
            found.update(copy.deepcopy(body or {}))
            if keep is not None:
                found["id"] = keep
            return self._response(204, {})
        if method == "PATCH":
            try:
                apply_patch(found, body or [])
            except (KeyError, IndexError, ValueError) as e:
                return self._response(422, {"message": "patch failed: %s" % e})
            return self._response(204, {})
        return self._response(405, {"message": "method not allowed"})

    def _find(self, items, ident):
        ident = urllib.parse.unquote(ident)
        for item in items:
            if str(item.get("id")) == ident or item.get("name") == ident or item.get("serverName") == ident:
                return item
        return None

    def _list(self, collection, items, qs):
        selected = []
        for item in items:
            ok = True
            for key, value in qs.items():
                if key in ("offset", "limit", "fields"):
                    continue
                if key in self.ignored_filters:
                    continue
                if key in item and str(item[key]) != value:     # an unknown filter is ignored, as on the lab
                    ok = False
            if ok:
                selected.append(item)
        offset = int(qs.get("offset", 0))
        limit = int(qs.get("limit", 100))
        page = [self._trim(collection, i, qs.get("fields")) for i in selected[offset:offset + limit]]
        if collection == "servers":
            self._tick_servers(selected)
        return self._response(200, {"resultSet": {"returnCount": len(page), "totalCount": len(selected)},
                                    "result": page})

    def _trim(self, collection, item, fields):
        keep = (set(fields.split(",")) | set(ALWAYS.get(collection, []))) if fields else None
        return {k: copy.deepcopy(v) for k, v in item.items()
                if not k.startswith("_") and (keep is None or k in keep)}

    def _create(self, collection, items, body):
        body = copy.deepcopy(body or {})
        name = body.get("name")
        if name is not None and collection not in DUPLICATES_OK and any(i.get("name") == name for i in items):
            return self._response(409, {"message": "%s already exists" % name})
        body.setdefault("id", uuid.uuid4().hex[:16])
        if collection == "loginRestrictionPolicies":
            body.setdefault("rules", [])        # a new policy starts with no rules, as on the lab
        items.append(body)
        return self._response(201, {}, {"Location": "https://st.example.com:8444%s%s/%s" % (API, collection, body["id"])})

    # -- certificates ---------------------------------------------------------
    def _import_certificate(self, data):
        text = data.decode("latin-1") if isinstance(data, bytes) else str(data)
        match = re.search(r"\{.*?\}", text, re.S)
        meta = json.loads(match.group(0)) if match else {}
        meta["id"] = uuid.uuid4().hex[:16]
        self.collections.setdefault("certificates", []).append(meta)
        return self._response(200, meta)

    def _export_certificate(self, cert_id, qs, files):
        if self._find(self.collections.get("certificates", []), cert_id) is None:
            return self._response(400, {"message": "no such certificate"})
        password = (files or {}).get("exportPassword")
        if not password or not (password[1] if isinstance(password, tuple) else password):
            return self._response(400, {"message": "Entity is empty."})
        return self._response(200, None, {"Content-Type": "application/octet-stream"}, raw=b"\x30\x82FAKE-PKCS12")

    # -- daemons, cluster services, the Transaction Manager --------------------
    def _operation(self, path, method, qs, entry):
        if method != "POST":
            return self._response(405, {"message": "method not allowed"})
        if path == "transactionManager/operations":
            entry["servers_active"] = [s.get("serverName") for s in self.collections.get("servers", [])
                                       if s.get("isActive")]
            self.objects.setdefault("transactionManager", {})["status"] = "Stopped."
            return self._response(200, {"message": "stopping"})
        op = qs.get("operation")
        if path == "daemons/operations":
            # as the reference says: daemon= names one daemon, and left out it means every daemon
            hit = []
            for s in self.collections.get("servers", []):
                if op == "stop" and qs.get("daemon") in (None, "", s.get("protocol")):
                    hit.append(s.get("serverName"))
                    s["_lag"] = self.stop_lag
                    if self.stop_lag == 0:
                        s["isActive"] = False
            entry["stopped"] = hit
            return self._response(200, {"daemonOperationResults": [
                {"daemon": qs.get("daemon") or "all", "message": "ok", "isSuccessful": True}]})
        for s in self.collections.get("clusterServices", []):
            if s.get("name") == qs.get("serviceName") and op == "stop":
                s["_lag"] = self.service_lag
                if self.service_lag == 0:
                    s["status"] = "Stopped."
        return self._response(200, {"message": "ok"})

    def _tick_servers(self, read):
        """A server that is being stopped goes down after stop_lag more reads that include it."""
        for s in read:
            if s.get("_lag") is not None and s.get("isActive"):
                if s["_lag"] <= 0:
                    s["isActive"] = False
                else:
                    s["_lag"] -= 1

    def _cluster_service(self, qs):
        for s in self.collections.get("clusterServices", []):
            if s.get("name") == qs.get("serviceName"):
                if s.get("_lag") is not None and s.get("status") == "Running.":
                    if s["_lag"] <= 0:
                        s["status"] = "Stopped."
                    else:
                        s["_lag"] -= 1
                return self._response(200, {"name": s["name"], "status": s["status"]})
        return self._response(404, {"message": "no such service"})


def apply_patch(doc, operations):
    """A small JSON Patch: add, replace and remove, with array indexes and the '-' of an append."""
    for op in operations:
        parts = [p for p in op["path"].split("/") if p != ""]
        target = doc
        for part in parts[:-1]:
            target = target[int(part)] if isinstance(target, list) else target[part]
        last = parts[-1]
        if isinstance(target, list):
            if op["op"] == "add":
                if last == "-":
                    target.append(op["value"])
                else:
                    if int(last) > len(target):
                        raise IndexError("Array index %s out of bounds" % last)
                    target.insert(int(last), op["value"])
            elif op["op"] == "replace":
                target[int(last)] = op["value"]
            else:
                del target[int(last)]
        else:
            if op["op"] == "replace" and last not in target:
                raise KeyError(last)
            if op["op"] == "remove":
                target[last] = None
            else:
                target[last] = op["value"]
