#!/usr/bin/env python3
"""
Every python example, run as a whole against a fake SecureTransport.

test_python_logic.py runs single functions out of an example. This runs the script,
main block and all, as its own process (tests/lib/run_example.py), with a stand-in for
the requests library that talks to an in-memory server (tests/lib/fake_requests). That
is the only way to see what a person sees: the exit code, a traceback, a worker process
that starts fresh, and whether a write would be accepted by a server that does what the
documentation says and the lab does not insist on.

What the fake server refuses, and so what every script is held to:

- a call with no Referer, or with another one than the login used;
- a call with no timeout;
- a write (POST, PUT, PATCH, DELETE, the logout too) that does not carry the csrfToken
  header the login answered with. The lab accepts such a write, which is why a script that
  forgot the header went unnoticed: this fake does not.

And what it does to each script (the matrix at the end): a connection error and a timeout
on every call, on the login only and after the login, a 401 and a 500 on the login, after
the login, and on one HTTP verb at a time. Every one must end the script with a non-zero
exit code and no traceback.

Runs offline. Exit code 0 means clean.
"""
import concurrent.futures
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import fake_st  # noqa: E402
import run_example  # noqa: E402
from example_worlds import (CERTIFICATES, MASTER_KEX, OPTIONS, SITES, SUBSCRIPTIONS, USERS,  # noqa: E402,F401
                            fixture, world)

failures = 0


class Case:
    def __init__(self, script, args=(), scenario=None, writes=(), reads_only=False, workers=False, **options):
        self.script = script
        self.workers = workers             # worker processes of its own: several logins, no fixed order
        self.args = list(args)
        self.scenario = scenario or {}
        self.writes = list(writes)         # (method, path) the clean run must send, in this order
        self.options = options             # files, edits, tree_files, env, start_method
        self.reads_only = reads_only

    def run(self, fail=None, **extra):
        scenario = dict(self.scenario)
        if fail:
            scenario["fail"] = fail
        options = dict(self.options)
        options.update(extra)
        return run_example.run(self.script, self.args, scenario, **options)


CASES = [
    Case("stAddLoginRestrictionRule.py", ["ZZ_policy"],
         world(loginRestrictionPolicies=[{"id": "p1", "name": "ZZ_policy", "type": "ALLOW_THEN_DENY", "rules": []}]),
         writes=[("PATCH", "loginRestrictionPolicies/ZZ_policy")]),
    Case("stBillableTransfers.py", ["2"], {"totals": {"logs/transfers": 3}}, reads_only=True),
    Case("stBuildFullTestAccount.py", [],
         world(routes=[{"id": "t1", "name": "Empty", "type": "TEMPLATE"}]),
         writes=[("POST", "accounts"), ("POST", "certificates"), ("POST", "sites"), ("POST", "sites"),
                 ("POST", "subscriptions"), ("POST", "routes"), ("POST", "routes")],
         files={"testsshkey": "-----BEGIN KEY-----\nnot a real key\n-----END KEY-----\n"}),
    Case("stBuildTestAccounts.py", ["--apply", "ZZ", "3"], world(),
         writes=[("POST", "businessUnits"), ("POST", "accounts"), ("POST", "accounts"), ("POST", "accounts")],
         workers=True, start_method="spawn"),
    Case("stCertificateExpiry.py", ["30"], world(certificates=CERTIFICATES), reads_only=True),
    Case("stConfigScan.py", ["MAKEBASELINE", "baseline.json"], world(**{"configurations/options": OPTIONS})),
    Case("stDeleteTestAccounts.py", ["--apply"], world(accounts=USERS),
         writes=[("DELETE", "accounts/ZZ0"), ("DELETE", "accounts/ZZ1")], workers=True, start_method="spawn"),
    Case("stGetAccountsAfterDate.py", ["2000-01-01"], world(accounts=USERS), reads_only=True),
    Case("stGetPrivateCert.py", ["c1"], world(certificates=CERTIFICATES),
         writes=[("POST", "certificates/c1/operations")], env={"ST_EXPORT_PASSWORD": "Pw_for_the_test_1"}),
    Case("stReplaceSites.py", ["--apply"], world(sites=SITES), writes=[("PUT", "sites/s1"), ("PUT", "sites/s3")]),
    Case("stUpdateAllAccounts.py", ["--apply"], world(accounts=USERS),
         writes=[("PATCH", "accounts/ZZtemplate")], tree_files={"python3/ST_API_client.pem": "not a real key"}),
    Case("stUpdateAllRoutes.py", ["--apply"], world(routes=fixture("routes.json")),
         writes=[("PATCH", "routes/r1"), ("PATCH", "routes/r1")]),
    Case("stUpdateAllSubscriptions.py", ["--apply"], world(subscriptions=SUBSCRIPTIONS),
         writes=[("PATCH", "subscriptions/s1"), ("PATCH", "subscriptions/s2")]),
    Case("stUpdateRouteWithPut.py", ["--apply", "c1"], world(routes=[fixture("composite_route.json")]),
         writes=[("PUT", "routes/c1")]),
    Case("stUsersPerSharedFolder.py", [], world(applications=fixture("applications.json"),
                                                subscriptions=fixture("sf_subscriptions.json")), reads_only=True),
]
for number, (name, expected) in enumerate((
        ("01.loginRestrictionPolicy_sessionExpression.py", [("POST", "loginRestrictionPolicies"), ("PATCH", "loginRestrictionPolicies/ZZTEST_EL_sessionLimit"),
                                                            ("DELETE", "loginRestrictionPolicies/ZZTEST_EL_sessionLimit")]),
        ("02.routes_condition_EL.py", [("POST", "routes")] * 3 + [("DELETE", "routes")] * 3),
        ("03.routes_step_fileFilterExpression_glob.py", [("POST", "routes")] * 4 + [("DELETE", "routes")] * 4),
        ("04.routes_step_fileFilterExpression_regexp.py", [("POST", "routes")] * 3 + [("DELETE", "routes")] * 3),
        ("05.routes_step_condition_matches_backslashDoubling.py", [("POST", "routes")] * 2 + [("DELETE", "routes")] * 2),
        ("06.routes_step_renameExpression.py", [("POST", "routes")] * 3 + [("DELETE", "routes")] * 3),
        ("07.transferSites_downloadPattern.py", [("POST", "sites")] * 3 + [("DELETE", "sites")] * 3),
        ("08.transferSites_dynamicProperties.py", [("POST", "sites"), ("DELETE", "sites")]))):
    CASES.append(Case("14.ExpressionLanguage/" + name, [], world(), writes=expected))

# the order of the writes of the EL scripts is "create, patch, delete" with the ids the server gave,
# so they are compared by verb and collection, not by id
EL_CASES = [c for c in CASES if c.script.startswith("14.")]


def same_writes(calls, expected, unordered=False):
    got = [(e["method"], e["path"]) for e in calls]
    want = list(expected)
    if unordered:
        got, want = sorted(got), sorted(want)
    if len(got) != len(want):
        return False
    for (m1, p1), (m2, p2) in zip(got, want):
        if m1 != m2 or not (p1 == p2 or p2 == p1.split("/")[0] or p1.startswith(p2 + "/")):
            return False
    return True


# ------------------------------------------------------------------- run them all
def clean_run(case):
    return case.run()


MODES = (("a connection error on every call", {"kind": "raise:ConnectionError"}),
         ("a timeout on every call", {"kind": "raise:Timeout"}),
         ("a read timeout on every call", {"kind": "raise:ReadTimeout"}),
         ("the login refused with 401", {"kind": "status:401", "on": "login"}),
         ("the login answering 500", {"kind": "status:500", "on": "login"}),
         ("a timeout after the login", {"kind": "raise:Timeout", "on": "after_login"}),
         ("a connection error after the login", {"kind": "raise:ConnectionError", "on": "after_login"}),
         ("401 after the login", {"kind": "status:401", "on": "after_login"}),
         ("500 after the login", {"kind": "status:500", "on": "after_login"}),
         ("500 on every GET", {"kind": "status:500", "on": "after_login", "method": "GET"}),
         ("a timeout on every GET", {"kind": "raise:Timeout", "on": "after_login", "method": "GET"}))

results = {}
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    clean = {case.script: pool.submit(clean_run, case) for case in CASES}
    for case in CASES:
        results[(case.script, "clean")] = clean[case.script].result()
    jobs = {}
    for case in CASES:
        used = {e["method"] for e in results[(case.script, "clean")].calls if e["path"] != "myself"}
        for label, fail in MODES:
            # a failure of a verb the script never uses changes nothing, so it is not asked for
            if fail.get("method") and fail["method"] not in used:
                continue
            jobs[(case.script, label)] = pool.submit(case.run, fail)
        for method in sorted(used - {"GET"}):
            jobs[(case.script, "500 on every %s" % method)] = pool.submit(
                case.run, {"kind": "status:500", "on": "after_login", "method": method})
            jobs[(case.script, "a timeout on every %s" % method)] = pool.submit(
                case.run, {"kind": "raise:Timeout", "on": "after_login", "method": method})
    results.update({key: job.result() for key, job in jobs.items()})

# ------------------------------------------------------------- the clean runs
c = fake_st.Checker("every python example: a clean run, held to what the documented server enforces")
for case in CASES:
    r = results[(case.script, "clean")]
    c.check("%s: exit code 0" % case.script, r.returncode == 0, (r.returncode, r.output[-300:]))
    c.check("%s: no traceback" % case.script, "Traceback" not in r.output, r.output[-300:])
    c.check("%s: no call was refused (a Referer, a timeout and the csrfToken on every write)" % case.script,
            r.violations() == [], r.violations())
    session_calls = [e for e in r.calls if e["path"] == "myself"]
    logins = [e for e in session_calls if e["method"] == "POST"]
    logouts = [e for e in session_calls if e["method"] == "DELETE"]
    c.check("%s: every login is followed by a logout, and the logout carries the csrfToken" % case.script,
            len(logins) >= 1 and len(logins) == len(logouts) and all(e["has_csrf"] for e in logouts)
            and (case.workers or len(logins) == 1), (len(logins), len(logouts)))
    if case.reads_only:
        c.check("%s: it writes nothing" % case.script, r.writes() == [], [(e["method"], e["path"]) for e in r.writes()])
    else:
        c.check("%s: it sends the writes it should, and only those" % case.script,
                same_writes(r.writes(), case.writes, case.workers), [(e["method"], e["path"]) for e in r.writes()])
        c.check("%s: every write carries the csrfToken" % case.script,
                all(e["has_csrf"] for e in r.writes()), [(e["method"], e["path"]) for e in r.writes() if not e["has_csrf"]])
failures += 0 if c.summary() else 1

# ------------------------------------------------------- the matrix of failures
print()
c = fake_st.Checker("every python example: a server that fails ends the script with a non-zero exit code and no traceback")
for (script, label), r in sorted(results.items()):
    if label == "clean":
        continue
    c.check("%s, %s: non-zero exit code, and it ends" % (script, label), r.returncode != 0 and not r.timed_out,
            (r.returncode, r.output[-200:]))
    c.check("%s, %s: no traceback" % (script, label), "Traceback" not in r.output, r.output[-300:])
failures += 0 if c.summary() else 1

# ----------------------------------------------------- the certificate check can be turned on
print()
c = fake_st.Checker("every python example: st_verify and st_ca_bundle in the config reach every call")
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    yes = {case.script: pool.submit(case.run, None, config={"st_verify": "yes"}) for case in CASES}
    bundle = {case.script: pool.submit(case.run, None, config={"st_ca_bundle": "/etc/ssl/example-ca.pem"}) for case in CASES}
    for case in CASES:
        r_default = results[(case.script, "clean")]
        c.check("%s: by default the certificate is not checked" % case.script,
                r_default.calls and all(e["verify"] is False for e in r_default.calls), set(e["verify"] for e in r_default.calls))
        r = yes[case.script].result()
        c.check("%s: st_verify=yes checks it on every call" % case.script,
                r.calls and all(e["verify"] is True for e in r.calls), (r.returncode, set(e["verify"] for e in r.calls)))
        r = bundle[case.script].result()
        c.check("%s: st_ca_bundle names the file it is checked against, on every call" % case.script,
                r.calls and all(e["verify"] == "/etc/ssl/example-ca.pem" for e in r.calls),
                (r.returncode, set(e["verify"] for e in r.calls)))
failures += 0 if c.summary() else 1

# ---------------------------------------------- the fake itself catches a missing csrfToken
print()
c = fake_st.Checker("the fake server refuses a write with no csrfToken, so a script that forgets it fails here")
probe = '''
import requests
s = requests.Session()
h = {"Referer": "R", "Accept": "application/json"}
r = s.post("https://st.example.com:8444/api/v2.0/myself", headers=dict(h, Authorization="Basic x"), timeout=5)
token = r.headers.get("csrfToken")
print("login", r.status_code, bool(token))
r = s.patch("https://st.example.com:8444/api/v2.0/routes/r1", headers=h, json=[], timeout=5)
print("write without the token", r.status_code)
r = s.patch("https://st.example.com:8444/api/v2.0/routes/r1", headers=dict(h, csrfToken=token), json=[], timeout=5)
print("write with the token", r.status_code)
r = s.get("https://st.example.com:8444/api/v2.0/routes", headers=dict(h, Referer="OTHER"), timeout=5)
print("another Referer", r.status_code)
r = s.get("https://st.example.com:8444/api/v2.0/routes", headers=h)
print("no timeout", r.status_code)
'''
import subprocess  # noqa: E402
import tempfile  # noqa: E402
scenario = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump(world(routes=[{"id": "r1", "name": "A"}]), scenario)
scenario.close()
done = subprocess.run([sys.executable, "-c", probe], capture_output=True, text=True,
                      env=dict(os.environ, PYTHONPATH=run_example.FAKE_REQUESTS, FAKE_ST_SCENARIO=scenario.name))
os.remove(scenario.name)
c.check("the login answers a csrfToken", "login 200 True" in done.stdout, done.stdout + done.stderr)
c.check("a write without it is 403", "write without the token 403" in done.stdout, done.stdout)
c.check("a write with it is accepted", "write with the token 204" in done.stdout, done.stdout)
c.check("a call with another Referer is 403", "another Referer 403" in done.stdout, done.stdout)
c.check("a call with no timeout is 403", "no timeout 403" in done.stdout, done.stdout)
failures += 0 if c.summary() else 1

print()
if failures:
    print("test_python_scripts_run: FAIL (%d group(s))" % failures)
    sys.exit(1)
print("test_python_scripts_run: PASS")
