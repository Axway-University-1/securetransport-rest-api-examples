#!/usr/bin/env python3
"""
The python examples again, for what the matrix of test_python_scripts_run.py and the safety tests do not reach. Each group answers a change
that a mutation probe (tools/mutation_probe.py) made to an example and no check noticed:

- the LOGOUT that fails, alone (the matrix fails every call after the login, so the script stops at an earlier call and the exit of its
  logout is never the one that decides);
- the exceptions the matrix never raises: an HTTPError and a generic RequestException on the login, on a read, on a write;
- a login that answers 200 but not "Logged in";
- the messages that tell a person what went wrong (the policy that is not there, a baseline that cannot be written, a certificate that is not
  there, a key file that is not there, a file that is not XML, a dry run, a logout that did not work);
- the config file: a comment line that holds an '=' is not a setting;
- what the two utils write in their log, and which call logs the session out;
- the body key and the query of calls that no other check reads.

Runs offline. Exit code 0 means clean.
"""
import ast
import concurrent.futures
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import fake_st  # noqa: E402
import run_example  # noqa: E402
from example_worlds import CERTIFICATES, SUBSCRIPTIONS, USERS, fixture, world  # noqa: E402

failures = 0
XML = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures")


def go(script, args=(), scenario=None, **kw):
    kw.setdefault("fast", True)
    kw.setdefault("allow_violations", True)
    return run_example.run(script, list(args), scenario if scenario is not None else world(), **kw)


def with_fail(scenario, fail):
    s = dict(scenario)
    s["fail"] = fail
    return s


# the scripts with a logout, a login, a read and a write of their own: (script, args, scenario, the verb of the write or None, extra options)
CALLERS = {
    "stBillableTransfers.py": (["2"], {"totals": {"logs/transfers": 3}}, None, {}),
    "stCertificateExpiry.py": (["30"], world(certificates=CERTIFICATES), None, {}),
    "stUsersPerSharedFolder.py": ([], world(applications=fixture("applications.json"), subscriptions=fixture("sf_subscriptions.json")), None, {}),
    "stUpdateAllRoutes.py": (["--apply"], world(routes=fixture("routes.json")), "PATCH", {}),
    "stUpdateAllSubscriptions.py": (["--apply"], world(subscriptions=SUBSCRIPTIONS), "PATCH", {}),
    "stUpdateRouteWithPut.py": (["--apply", "c1"], world(routes=[fixture("composite_route.json")]), "PUT", {}),
}
LOGOUT = {"kind": "raise:ConnectionError", "on": "after_login", "method": "DELETE", "path": "myself"}
jobs = []
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    for script, (args, scenario, verb, kw) in CALLERS.items():
        runs = [("logout fails alone", LOGOUT, "I cannot connect to"),
                ("login: HTTPError", {"kind": "raise:HTTPError", "on": "login"}, "HTTP Error"),
                ("login: RequestException", {"kind": "raise:RequestException", "on": "login"}, "Unknown Error"),
                ("a read: HTTPError", {"kind": "raise:HTTPError", "on": "after_login", "method": "GET"}, "HTTP Error")]
        if verb:
            runs.append(("a %s: HTTPError" % verb, {"kind": "raise:HTTPError", "on": "after_login", "method": verb}, "HTTP Error"))
        for label, fail, phrase in runs:
            jobs.append((script, label, phrase, pool.submit(go, script, args, with_fail(scenario, fail), **kw)))
c = fake_st.Checker("a failing logout, and the exceptions the matrix never raises: exit 1, the message, no traceback")
for script, label, phrase, job in jobs:
    r = job.result()
    c.check("%s, %s: exit 1 and '%s'" % (script, label, phrase), r.returncode == 1 and phrase in r.output and "Traceback" not in r.output,
            (r.returncode, r.output[-200:]))
failures += 0 if c.summary() else 1

# ------------------------------------------------------------- a login that does not answer "Logged in"
print()
c = fake_st.Checker("a login that answers 200 and not \"Logged in\": the script says so, exits non-zero and writes nothing")
LOGIN_SCRIPTS = (("stAddLoginRestrictionRule.py", ["ZZ_policy"],
                  world(loginRestrictionPolicies=[{"id": "p1", "name": "ZZ_policy", "type": "ALLOW_THEN_DENY", "rules": []}]), {}),
                 ("stBuildTestAccounts.py", ["--apply", "ZZ", "3"], world(), {"start_method": "spawn"}),
                 ("stConfigScan.py", ["MAKEBASELINE", "baseline.json"], world(), {}),
                 ("stDeleteTestAccounts.py", ["--apply"], world(accounts=USERS), {"start_method": "spawn"}),
                 ("stGetPrivateCert.py", ["c1"], world(certificates=CERTIFICATES), {"env": {"ST_EXPORT_PASSWORD": "Pw_for_the_test_1"}}))
for script, args, scenario, kw in LOGIN_SCRIPTS:
    r = go(script, args, dict(scenario, login_message="Welcome"), **kw)
    c.check("%s: exit non-zero, 'The login did not answer \"Logged in\"', no write" % script,
            r.returncode != 0 and 'The login did not answer "Logged in"' in r.output and r.writes() == [], (r.returncode, r.output[-200:]))
failures += 0 if c.summary() else 1

# ------------------------------------------------------------- messages that tell a person what went wrong
print()
c = fake_st.Checker("what a person is told when the thing the script needs is not there")
r = go("stAddLoginRestrictionRule.py", ["ZZ_unknown"], world(loginRestrictionPolicies=[{"id": "p1", "name": "ZZ_policy", "type": "ALLOW_THEN_DENY", "rules": []}]))
c.check("stAddLoginRestrictionRule, a policy that does not exist: exit non-zero, says which, no write",
        r.returncode != 0 and "I cannot Find the Login Restriction named: ZZ_unknown" in r.output and r.writes() == [], (r.returncode, r.output[-200:]))
r = go("stAddLoginRestrictionRule.py", ["ZZ_policy"], world(loginRestrictionPolicies=[{"id": "p1", "name": "ZZ_policy", "type": "ALLOW_THEN_DENY", "rules": []}]))
c.check("stAddLoginRestrictionRule, a policy that exists: it does not say it cannot find it", r.returncode == 0 and "I cannot Find" not in r.output, (r.returncode, r.output[-200:]))
r = go("stConfigScan.py", ["MAKEBASELINE", "no_such_folder/baseline.json"], world(**{"configurations/options": [{"name": "A.One", "values": ["1"]}]}))
c.check("stConfigScan, a baseline that cannot be written: exit 1 and 'I cannot write the baseline'",
        r.returncode == 1 and "I cannot write the baseline" in r.output and "Traceback" not in r.output, (r.returncode, r.output[-200:]))
r = go("stBuildFullTestAccount.py", [], world(routes=[{"id": "t1", "name": "Empty", "type": "TEMPLATE"}]), files={"testsshkey": "-----BEGIN KEY-----\nx\n-----END KEY-----\n"})
clean_full = r
c.check("stBuildFullTestAccount, a clean run does not say it cannot find the certificate", "I cannot find the Certificate" not in clean_full.output, clean_full.output[-200:])
r = go("stBuildFullTestAccount.py", [], world(routes=[{"id": "t1", "name": "Empty", "type": "TEMPLATE"}]))
c.check("stBuildFullTestAccount, with no key file: exit non-zero and 'I cannot read the private key file testsshkey'",
        r.returncode != 0 and "I cannot read the private key file testsshkey" in r.output, (r.returncode, r.output[-200:]))
r = go("../utils/stCompareExportedConfigurations.py", ["a.xml", "b.xml"], world(), files={"a.xml": "<a", "b.xml": "<a/>"})
c.check("stCompareExportedConfigurations, a file that is not XML: exit 1, 'is not valid XML', no traceback",
        r.returncode == 1 and "The file a.xml is not valid XML" in r.output and "Traceback" not in r.output, (r.returncode, r.output[-200:]))
r = go("../utils/stCompareExportedConfigurations.py", ["a.xml", "missing.xml"], world(), files={"a.xml": "<a/>"})
c.check("stCompareExportedConfigurations, a file that is not there: exit 1, 'I cannot read the file: missing.xml'",
        r.returncode == 1 and "I cannot read the file: missing.xml" in r.output, (r.returncode, r.output[-200:]))
r = go("../utils/processSystemConfig.py", ["missing.xml"], world())
c.check("processSystemConfig, a file that is not there: exit 1, 'I cannot read the file: missing.xml'",
        r.returncode == 1 and "I cannot read the file: missing.xml" in r.output, (r.returncode, r.output[-200:]))
r = go("stUpdateAllRoutes.py", [], world(routes=fixture("routes.json")))
c.check("stUpdateAllRoutes, with no --apply: a dry run says what it would send and sends no write",
        r.returncode == 0 and "DRY RUN, would send:" in r.output and r.writes() == [], (r.returncode, r.writes(), r.output[-200:]))
r = go("stUpdateAllRoutes.py", ["--apply"], world(routes=fixture("routes.json")))
c.check("stUpdateAllRoutes, with --apply: it does not say it is a dry run", "DRY RUN" not in r.output and len(r.writes()) >= 1, (r.writes(), r.output[-200:]))
r = go("stUpdateAllSubscriptions.py", ["--apply"], with_fail(world(subscriptions=SUBSCRIPTIONS), {"kind": "status:401", "on": "login"}))
c.check("stUpdateAllSubscriptions, the login refused (401): exit non-zero and 'Cannot login  401'", r.returncode != 0 and "Cannot login  401" in r.output, (r.returncode, r.output[-200:]))
r = go("stUpdateAllSubscriptions.py", ["--apply"], dict(world(subscriptions=SUBSCRIPTIONS), login_message="Welcome"))
c.check("stUpdateAllSubscriptions, a login that answers 200 and not 'Logged in': exit non-zero and 'Login Failure'", r.returncode != 0 and "Login Failure" in r.output and r.writes() == [], (r.returncode, r.output[-200:]))
r = go("stUpdateAllSubscriptions.py", ["--apply"], with_fail(world(subscriptions=SUBSCRIPTIONS), {"kind": "status:500", "on": "after_login", "method": "GET"}))
c.check("stUpdateAllSubscriptions, the list refused: exit non-zero and 'GET subscriptions returned 500'", r.returncode != 0 and "GET subscriptions returned 500" in r.output, (r.returncode, r.output[-200:]))
GRACEFUL_WORLD = {"collections": {"servers": [{"serverName": "Ssh Default", "protocol": "ssh", "isActive": True}, {"serverName": "Ftp Default", "protocol": "ftp", "isActive": True},
                                              {"serverName": "Http One", "protocol": "http", "isActive": True}, {"serverName": "Pesit Default", "protocol": "pesit", "isActive": True},
                                              {"serverName": "As2 Default", "protocol": "as2", "isActive": False}],
                                 "clusterServices": [{"name": "FolderMonitor", "status": "Running."}, {"name": "Scheduler", "status": "Running."}]},
                  "objects": {"transactionManager": {"status": "Running."}}}
r = go("stGraceful.py", ["30", "--yes"], with_fail(GRACEFUL_WORLD, {"kind": "status:500", "on": "after_login", "method": "DELETE", "path": "myself"}))
c.check("stGraceful, a logout that did not work: it says so (and goes on, as it says)", "did not work; everything was stopped all the same" in r.output, r.output[-300:])
r = go("stGraceful.py", ["30", "--yes"], GRACEFUL_WORLD)
c.check("stGraceful, a logout that worked: it does not say it did not", "did not work; everything was stopped all the same" not in r.output, r.output[-300:])
failures += 0 if c.summary() else 1

# ------------------------------------------------------------- what the scripts print that a person reads
print()
c = fake_st.Checker("the result lines a person reads at the end")
r = go("stGetAccountsAfterDate.py", ["2000-01-01"], world(accounts=USERS))
c.check("stGetAccountsAfterDate says how many accounts were created in the period (2)", re.search(r"There were:\s+2\s+created in this time period", r.output) is not None, r.output[-200:])
r = go("stDeleteTestAccounts.py", ["ZZ"], world(accounts=USERS))
c.check("stDeleteTestAccounts says how many of how many accounts start with the prefix", "2 of 5 user accounts have a name that starts with ZZ" in r.output, r.output[-300:])
r = go("stCertificateExpiry.py", ["30"], world(certificates=CERTIFICATES))
c.check("stCertificateExpiry ends with the number of calls it made (3)", "Completed Run, number of APIs issued: 3" in r.output, r.output[-200:])
r = go("stGetPrivateCert.py", ["c1"], world(certificates=CERTIFICATES), env={"ST_EXPORT_PASSWORD": "Pw_for_the_test_1"})
c.check("stGetPrivateCert says the file it wrote", "Private Key exported with filename exportedPrivateKey.p12" in r.output, r.output[-200:])
r = go("stUpdateRouteWithPut.py", ["--apply", "c1"], world(routes=[fixture("composite_route.json")]))
c.check("stUpdateRouteWithPut says how many steps the route has before it changes it", "Route Composite1 has 2 steps" in r.output, r.output[-200:])
puts = [e for e in r.writes() if e["method"] == "PUT"]
sent = json.loads(puts[0]["data"]) if puts and puts[0].get("data") else (puts[0]["body"] if puts else {})
steps = sent.get("routeSteps") or sent.get("steps") or []
c.check("stUpdateRouteWithPut sends a step of type EncodingConversion, first (the offset is 0)", steps and steps[0].get("type") == "EncodingConversion", [s.get("type") for s in steps])
failures += 0 if c.summary() else 1

# ------------------------------------------------------------- the readback queries of the EL examples, and the logout of the util
print()
c = fake_st.Checker("the calls no other check reads: the readback of an Expression Language example, the logout of a util")
for script, collection in (("14.ExpressionLanguage/02.routes_condition_EL.py", "routes"), ("14.ExpressionLanguage/08.transferSites_dynamicProperties.py", "sites")):
    r = go(script, [], world())
    reads = [e for e in r.calls if e["method"] == "GET" and e["path"] == collection and "fields" in e["query"]]
    c.check("%s: the readback asks for the object it made, by name" % script,
            reads and all(e["query"].get("name", "").startswith("ZZTEST") for e in reads), [e["query"] for e in reads])
userclasses = open(os.path.join(XML, "userclasses.xml")).read()
turn_on = {"createOnTarget = False": "createOnTarget = True"}
r = go("../utils/processSystemConfig.py", ["uc.xml"], world(), files={"uc.xml": userclasses}, edits=turn_on)
c.check("processSystemConfig ends the session with a DELETE of /myself", r.calls and (r.calls[-1]["method"], r.calls[-1]["path"]) == ("DELETE", "myself"),
        [(e["method"], e["path"]) for e in r.calls][-3:])
for label, fail, phrase in (("the logout alone fails", LOGOUT, "I cannot connect to"),
                            ("the login times out (a read timeout)", {"kind": "raise:ReadTimeout", "on": "login"}, "Timeout"),
                            ("a user class POST raises a RequestException", {"kind": "raise:RequestException", "on": "after_login", "method": "POST", "path": "userClasses"}, "Unknown Error"),
                            ("a user class POST raises an HTTPError", {"kind": "raise:HTTPError", "on": "after_login", "method": "POST", "path": "userClasses"}, "HTTP Error")):
    r = go("../utils/processSystemConfig.py", ["uc.xml"], with_fail(world(), fail), files={"uc.xml": userclasses}, edits=turn_on)
    c.check("processSystemConfig, %s: exit 1 and '%s'" % (label, phrase), r.returncode == 1 and phrase in r.output and "Traceback" not in r.output, (r.returncode, r.output[-200:]))
failures += 0 if c.summary() else 1

# ------------------------------------------------------------- the log the utils write
print()
c = fake_st.Checker("the log of the two utils: SUCCESS and WARNING lines are padded, the others have one space")
r = go("../utils/stCompareExportedConfigurations.py", ["a.xml", "b.xml"], world(), files={"a.xml": "<a><b>1</b></a>", "b.xml": "<a><b>2</b></a>"})
log = (r.read("compareXML.log", "script") or b"").decode()
c.check("stCompareExportedConfigurations: the INFORMATION lines have one space after the severity", log and re.search(r"INFORMATION \S", log) and not re.search(r"INFORMATION  ", log), log[:200])
r = go("../utils/processSystemConfig.py", ["uc.xml"], world(), files={"uc.xml": userclasses}, edits=turn_on)
log = (r.read("extractUserClasses.log", "script") or b"").decode()
c.check("processSystemConfig: the INFORMATION lines have one space after the severity", log and re.search(r"INFORMATION \S", log) and not re.search(r"INFORMATION  ", log), log[:200])
failures += 0 if c.summary() else 1

# ------------------------------------------------------------- a comment in the config file is not a setting
print()
c = fake_st.Checker("a comment line of the config file that holds an '=' is not a setting")
CONFIG_SCRIPTS = (("stBuildFullTestAccount.py", [], world(routes=[{"id": "t1", "name": "Empty", "type": "TEMPLATE"}]), {"files": {"testsshkey": "-----BEGIN KEY-----\nx\n-----END KEY-----\n"}}),
                  ("stBuildTestAccounts.py", ["--apply", "ZZ", "3"], world(), {"start_method": "spawn"}),
                  ("stCertificateExpiry.py", ["30"], world(certificates=CERTIFICATES), {}),
                  ("stDeleteTestAccounts.py", ["--apply"], world(accounts=USERS), {"start_method": "spawn"}),
                  ("stGetPrivateCert.py", ["c1"], world(certificates=CERTIFICATES), {"env": {"ST_EXPORT_PASSWORD": "Pw_for_the_test_1"}}),
                  ("stUpdateRouteWithPut.py", ["--apply", "c1"], world(routes=[fixture("composite_route.json")]), {}))
CONFIG = ('# the settings of this server\n\nst_server="st.example.com"\nst_port="8444"\nst_user="apiadmin"\nst_password="not-a-real-password"\n'
          '# st_server="other.example.com"\n# st_port="1"\n\n')
for script, args, scenario, kw in CONFIG_SCRIPTS:
    kw = dict(kw, tree_files={"config": CONFIG})
    r = go(script, args, scenario, **kw)
    hosts = {re.match(r"https://([^/]+)/", e["url"]).group(1) for e in r.calls}
    c.check("%s: every call goes to st.example.com:8444, whatever the comment lines say" % script, r.returncode == 0 and hosts == {"st.example.com:8444"},
            (r.returncode, hosts, r.output[-150:]))
failures += 0 if c.summary() else 1


# ------------------------------------------------------------- more messages a person reads, and the Expression Language examples' own output
print()
c = fake_st.Checker("what the examples print: a timeout, a certificate that is not found, the steps of an Expression Language example")
r = go("stBuildFullTestAccount.py", [], world(routes=[{"id": "t1", "name": "Empty", "type": "TEMPLATE"}],
                                                certificates=[{"id": "x1", "name": "PrivateSSHKey", "usage": "private", "account": "TestAccount1"}]),
       files={"testsshkey": "-----BEGIN KEY-----\nx\n-----END KEY-----\n"})
c.check("stBuildFullTestAccount, two certificates where one is expected: exit 1 and 'I cannot find the Certificate'",
        r.returncode == 1 and "I cannot find the Certificate" in r.output, (r.returncode, r.output[-200:]))
for script, args, scenario, kw in (("stBuildFullTestAccount.py", [], world(routes=[{"id": "t1", "name": "Empty", "type": "TEMPLATE"}]), {"files": {"testsshkey": "-----BEGIN KEY-----\nx\n-----END KEY-----\n"}}),
                                   ("stBuildTestAccounts.py", ["--apply", "ZZ", "3"], world(), {"start_method": "spawn"}),
                                   ("stDeleteTestAccounts.py", ["--apply"], world(accounts=USERS), {"start_method": "spawn"}),
                                   ("stReplaceSites.py", ["--apply"], world(sites=fixture("subscriptions.json") and [{"id": "s1", "name": "PartnerOne", "protocol": "ssh", "account": "john", "keyExchangeAlgorithms": "old-kex"}]), {})):
    for label, fail in (("a timeout after the login", {"kind": "raise:Timeout", "on": "after_login"}), ("a read timeout after the login", {"kind": "raise:ReadTimeout", "on": "after_login"})):
        r = go(script, args, with_fail(scenario, fail), **kw)
        c.check("%s, %s: exit 1 and 'Timeout talking to'" % (script, label), r.returncode == 1 and "Timeout talking to" in r.output and "Traceback" not in r.output, (r.returncode, r.output[-200:]))
r = go("stCertificateExpiry.py", ["30"], with_fail(world(certificates=CERTIFICATES), {"kind": "status:500", "on": "after_login", "method": "GET", "path": "certificates"}))
c.check("stCertificateExpiry, the list refused: 'GET certificates returned 500', and the answer's text, exit 1",
        r.returncode == 1 and "GET certificates returned 500" in r.output and "fake failure" in r.output, (r.returncode, r.output[-200:]))
r = go("stCertificateExpiry.py", ["30"], world(certificates=[{"id": "c1", "name": "no end date", "usage": "private"}]))
c.check("stCertificateExpiry, a certificate with no end date field: says to set expiryFieldName, then 'Completed Run', exit 1",
        r.returncode == 1 and "Set expiryFieldName in the configuration section to the right one." in r.output and "Completed Run, number of APIs issued:" in r.output,
        (r.returncode, r.output[-300:]))
r = go("stBillableTransfers.py", ["2"], {"objects": {"logs/transfers": {"resultSet": {}}}})
c.check("stBillableTransfers, an answer with no count: 'could not read a count' for each of the 2 days, INCOMPLETE, exit 1",
        r.returncode == 1 and r.output.count("could not read a count") == 2 and "INCOMPLETE" in r.output, (r.returncode, r.output[-300:]))
r = go("stUpdateAllRoutes.py", ["--apply"], with_fail(world(routes=fixture("routes.json")), {"kind": "raise:RequestException", "on": "after_login", "method": "GET"}))
c.check("stUpdateAllRoutes, a read that raises a RequestException: exit 1 and 'Unknown Error'", r.returncode == 1 and "Unknown Error" in r.output, (r.returncode, r.output[-200:]))
r = go("../utils/processSystemConfig.py", ["uc.xml"], with_fail(world(), {"kind": "raise:HTTPError", "on": "login"}), files={"uc.xml": userclasses}, edits=turn_on)
c.check("processSystemConfig, an HTTPError on the login: exit 1 and 'HTTP Error'", r.returncode == 1 and "HTTP Error" in r.output, (r.returncode, r.output[-200:]))
r = go("../utils/stCompareExportedConfigurations.py", ["a.xml", "b.xml"], world(), files={"a.xml": "<a><b>1</b></a>", "b.xml": "<a><b>2</b></a>"})
c.check("stCompareExportedConfigurations prints what it logs (the 'Completed Run' line, with the counts)", re.search(r"Completed Run\. \d+ differing, \d+ only in file 1, \d+ only in file 2\.", r.output) is not None, r.output[-200:])
# the six Expression Language examples: the steps they say they are on, the status of each call, and the answer they read back
EL = ("01.loginRestrictionPolicy_sessionExpression.py", "02.routes_condition_EL.py", "03.routes_step_fileFilterExpression_glob.py",
      "06.routes_step_renameExpression.py", "07.transferSites_downloadPattern.py", "08.transferSites_dynamicProperties.py")
# the lines each example must print are read from the example as it is in the repository (not from the copy a run uses: a probe changes that one)
REPO_PYDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "Admin", "API 2.0", "python")
for name in EL:
    path = os.path.join(REPO_PYDIR, "python3", "14.ExpressionLanguage", name)
    source = open(path).read()
    headings = []
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Call) and getattr(node.func, "id", "") == "print" and node.args:
            a0 = node.args[0]
            text = a0.value if isinstance(a0, ast.Constant) and isinstance(a0.value, str) else (
                a0.left.value if isinstance(a0, ast.BinOp) and isinstance(a0.left, ast.Constant) and isinstance(a0.left.value, str) else "")
            text = text.strip().split("%")[0].strip()
            if len(text) >= 6:
                headings.append(text)
    r = go("14.ExpressionLanguage/" + name, [], world())
    missing = [h for h in headings if h and h not in r.output]
    c.check("%s: it prints each step it says it is on (%d of them)" % (name, len(headings)), r.returncode == 0 and headings and not missing, (missing, r.output[-200:]))
    c.check("%s: it prints the status of a call (201)" % name, re.search(r"^201\b", r.output, re.M) is not None, r.output[-300:])
    c.check("%s: it prints an answer it read back (a JSON line)" % name, re.search(r"^[\[{]", r.output, re.M) is not None, r.output[-300:])
failures += 0 if c.summary() else 1

print()
if failures:
    print("test_python_survivors: FAIL (%d group(s))" % failures)
    sys.exit(1)
print("test_python_survivors: PASS")
