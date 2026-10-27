#!/usr/bin/env python3
"""The stand-in for `requests` (tests/offline/lib/fake_requests): what it refuses for what a script sends, so that a script that stops sending it fails
every test that runs it: no Referer, a write with no csrfToken, a call in a session with no csrfToken, a JSON body with no Content-Type, a resource that
does not exist. A refused call makes the run exit 97."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import fake_st  # noqa: E402,F401  (puts the stand-in on the path for run_example)
import run_example  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


PROBE = """
import json, sys, requests
URL = "https://st.example.com:8444/api/v2.0/"
H = {"Referer": "THIS_IS_A_RANDOM_TEXT"}
s = requests.Session()
r = s.post(URL + "myself", headers=dict(H, Authorization="Basic eA=="), verify=False, timeout=10)
tok = r.headers.get("csrfToken")
mode = sys.argv[1]
good = dict(H, csrfToken=tok)
if mode == "ok":
    s.get(URL + "accounts", headers=good, verify=False, timeout=10)
    s.post(URL + "accounts", headers=dict(good, **{"Content-Type": "application/json"}), data=json.dumps({"name": "ZZ"}), verify=False, timeout=10)
    s.post(URL + "accounts", headers=good, json={"name": "ZY"}, verify=False, timeout=10)
elif mode == "get_without_token":
    s.get(URL + "accounts", headers=H, verify=False, timeout=10)
elif mode == "json_without_type":
    s.post(URL + "accounts", headers=good, data=json.dumps({"name": "ZZ"}), verify=False, timeout=10)
elif mode == "unknown_resource":
    s.get(URL + "xaccounts", headers=good, verify=False, timeout=10)
elif mode == "no_referer":
    s.get(URL + "accounts", headers={"csrfToken": tok}, verify=False, timeout=10)
"""


def probe(mode, scenario=None, allow=False):
    return run_example.run("zz_probe.py", [mode], scenario=scenario or {}, tree_files={"python3/zz_probe.py": PROBE}, fast=True, allow_violations=allow)


r = probe("ok")
check("a script that sends everything is not refused", r.returncode == 0 and r.violations() == [], (r.returncode, r.violations(), r.output[-200:]))
for mode, why in (("get_without_token", "a call in a session with no csrfToken header"), ("json_without_type", "a JSON body with no Content-Type header"),
                  ("unknown_resource", "a resource that does not exist: xaccounts"), ("no_referer", "no Referer header")):
    r = probe(mode)
    check("%s: refused (%s), and the run exits 97" % (mode, why), r.returncode == 97 and any(why in v[2] for v in r.violations()), (r.returncode, r.violations()))
r = probe("json_without_type", allow=True)
check("allow_violations=True leaves the exit code of the script, for a test about such a call", r.returncode == 0 and r.violations(), (r.returncode, r.violations()))
r = probe("unknown_resource", scenario={"strict": False})
check('scenario "strict": false turns the three rules off', r.returncode == 0 and r.violations() == [], (r.returncode, r.violations()))
r = probe("unknown_resource", scenario={"collections": {"xaccounts": []}})
check("a collection the scenario brings is a resource", r.returncode == 0 and r.violations() == [], (r.returncode, r.violations()))
print("test_fake_requests: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
