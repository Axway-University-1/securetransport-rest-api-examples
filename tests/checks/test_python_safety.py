#!/usr/bin/env python3
"""
What each python example does with the objects it can destroy, the secrets it handles
and the files it writes, run as a whole against the fake server (tests/lib/run_example.py).

test_python_scripts_run.py holds every script to the same rules (csrfToken, exit codes).
This is the part that is each script's own: a delete that matches by prefix and not by
substring, a dry run that is the default, a private key written to a file only its owner
can read, a cleanup that deletes only what it created.

Runs offline. Exit code 0 means clean.
"""
import json
import os
import stat
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import fake_st  # noqa: E402
import run_example  # noqa: E402
from example_worlds import CERTIFICATES, MASTER_KEX, OPTIONS, SITES, SUBSCRIPTIONS, USERS, fixture, world  # noqa: E402

failures = 0


def paths(result, verb):
    return sorted(e["path"] for e in result.writes() if e["method"] == verb)


# ============================================================== stDeleteTestAccounts.py
c = fake_st.Checker("stDeleteTestAccounts.py: a dry run by default, an anchored prefix, only user accounts, true counts")
SCRIPT = "stDeleteTestAccounts.py"

r = run_example.run(SCRIPT, [], world(accounts=USERS))
c.check("with no argument it deletes nothing: exit 0, no DELETE", r.returncode == 0 and r.writes() == [], (r.returncode, r.writes()))
c.check("it lists what it WOULD delete, and says it is a dry run",
        "ZZ0" in r.output and "ZZ1" in r.output and "DRY RUN" in r.output and "--apply" in r.output, r.output)
c.check("the list holds only names that START with ZZ (not myZZ, not zz9)",
        "myZZ" not in r.output and "zz9" not in r.output.replace("DRY", ""), r.output)

lists = [e for e in r.calls if e["method"] == "GET" and e["path"] == "accounts"]
c.check("it lists with type=user, the filter the reference has", lists and all(e["query"].get("type") == "user" for e in lists), lists[:1])
c.check("and no longer sends the accountType= the API ignores", all("accountType" not in e["query"] for e in lists), lists[:1])

r = run_example.run(SCRIPT, ["--apply"], world(accounts=USERS), start_method="spawn")
c.check("--apply deletes exactly the user accounts that start with ZZ", paths(r, "DELETE") == ["accounts/ZZ0", "accounts/ZZ1"],
        paths(r, "DELETE"))
c.check("exit 0, and it says how many it deleted", r.returncode == 0 and "Deleted 2 of 2 accounts" in r.output, (r.returncode, r.output[-300:]))
c.check("under spawn, the way macOS and Windows start a worker, no worker fails with a NameError",
        "NameError" not in r.output and "Traceback" not in r.output, r.output[-500:])

r = run_example.run(SCRIPT, ["--apply"], world(accounts=USERS), start_method="fork")
c.check("under fork as well", paths(r, "DELETE") == ["accounts/ZZ0", "accounts/ZZ1"] and r.returncode == 0, (paths(r, "DELETE"), r.returncode))

# A server that ignores type= (as the lab ignored accountType=) answers every account: the template and the service stay
r = run_example.run(SCRIPT, ["--apply"], dict(world(accounts=USERS), ignore_filters=["type"]), start_method="spawn")
c.check("a template or service account whose name starts with ZZ is not deleted even if the server ignores type=",
        paths(r, "DELETE") == ["accounts/ZZ0", "accounts/ZZ1"], paths(r, "DELETE"))

r = run_example.run(SCRIPT, ["--apply", "zz"], world(accounts=USERS), start_method="spawn")
c.check("the prefix is an argument, and case sensitive", paths(r, "DELETE") == ["accounts/zz9"], paths(r, "DELETE"))
r = run_example.run(SCRIPT, ["Z", "--apply"], world(accounts=USERS))
c.check("a prefix of one character would match too much: exit 2, nothing sent", r.returncode == 2 and r.calls == [], (r.returncode, r.calls[:1]))
r = run_example.run(SCRIPT, ["ZZ", "ZY"], world(accounts=USERS))
c.check("two prefixes: exit 2, nothing sent", r.returncode == 2 and r.calls == [], r.returncode)

r = run_example.run(SCRIPT, ["--apply"], dict(world(accounts=USERS), fail={"kind": "status:500", "on": "after_login", "method": "DELETE",
                                                                        "path": "accounts/ZZ1"}), start_method="spawn")
c.check("a DELETE the server answers 500 is not counted as deleted", "Deleted 1 of 2 accounts" in r.output, r.output[-400:])
c.check("and the exit code is 1", r.returncode == 1, r.returncode)

r = run_example.run(SCRIPT, ["--apply"], world(accounts=[{"id": "x", "name": "john", "type": "user"}]), start_method="spawn")
c.check("nothing to delete is exit 0 and no worker is started", r.returncode == 0 and r.writes() == [], (r.returncode, r.output[-200:]))

many = [{"id": "n%d" % i, "name": "ZZ%d" % i, "type": "user"} for i in range(250)]
r = run_example.run(SCRIPT, ["--apply"], world(accounts=many), start_method="spawn", timeout=60)
c.check("250 accounts, over several pages and three workers: all of them deleted, once each",
        paths(r, "DELETE") == sorted("accounts/ZZ%d" % i for i in range(250)) and r.returncode == 0, (len(paths(r, "DELETE")), r.returncode))
failures += 0 if c.summary() else 1

# ============================================================== stBuildTestAccounts.py
print()
c = fake_st.Checker("stBuildTestAccounts.py: a dry run by default, the prefix and the count from the command line, workers that end")
SCRIPT = "stBuildTestAccounts.py"
r = run_example.run(SCRIPT, [], world())
c.check("with no argument it creates nothing and sends nothing: exit 0, no call", r.returncode == 0 and r.calls == [], (r.returncode, r.calls[:1]))
c.check("it says what it would create", "DRY RUN" in r.output and "ZZ0" in r.output and "100 user accounts" in r.output, r.output)

r = run_example.run(SCRIPT, ["--apply", "QA", "4"], world(), start_method="spawn")
posts = [e for e in r.writes() if e["path"] == "accounts"]
c.check("the prefix and the count are arguments", sorted(e["body"]["name"] for e in posts) == ["QA0", "QA1", "QA2", "QA3"],
        sorted(e["body"]["name"] for e in posts))
c.check("exit 0 under spawn, with no NameError in a worker", r.returncode == 0 and "NameError" not in r.output, r.output[-500:])
c.check("it ends: the workers get an end marker each and do not wait on a timeout that was never honoured",
        not r.timed_out)

r = run_example.run(SCRIPT, ["--apply", "ZZ", "2"], world(businessUnits=[{"id": "b1", "name": "CatFoodCorporation"}]), start_method="spawn")
c.check("a business unit that is there already is left as it is, not created again",
        [e for e in r.writes() if e["path"] == "businessUnits"] == [] and r.returncode == 0, (r.returncode, r.output[-300:]))

r = run_example.run(SCRIPT, ["--apply", "ZZ", "3"], world(accounts=[{"id": "x", "name": "ZZ1", "type": "user"}]), start_method="spawn")
c.check("an account that cannot be created (it is there) is exit 1, and says so", r.returncode == 1 and "ZZ1" in r.output, (r.returncode, r.output[-400:]))
c.check("and the others are still made", len([e for e in r.writes() if e["path"] == "accounts"]) == 3, len(r.writes()))

for args in (["ZZ", "many"], ["ZZ", "3", "4"], ["Z"], ["ZZ", "0"], ["a/b"]):
    r = run_example.run(SCRIPT, ["--apply"] + args, world())
    c.check("arguments %s: exit 2, nothing sent" % args, r.returncode == 2 and r.calls == [], (r.returncode, r.calls[:1]))
failures += 0 if c.summary() else 1

# ================================================================ stReplaceSites.py
print()
c = fake_st.Checker("stReplaceSites.py: a dry run by default, the whole site sent back, a refused PUT is a failure")
SCRIPT = "stReplaceSites.py"
r = run_example.run(SCRIPT, [], world(sites=SITES))
c.check("with no argument it changes nothing: exit 0, no PUT", r.returncode == 0 and r.writes() == [], (r.returncode, r.writes()))
c.check("it names the sites it would change", "PartnerOne" in r.output and "PartnerThree" in r.output and "DRY RUN" in r.output, r.output)
c.check("and does not claim to have patched anything", "Successfully" not in r.output, r.output)

r = run_example.run(SCRIPT, ["--apply"], world(sites=SITES))
puts = {e["path"]: e["body"] for e in r.writes() if e["method"] == "PUT"}
c.check("--apply replaces the SSH sites that differ, and only those", sorted(puts) == ["sites/s1", "sites/s3"], sorted(puts))
c.check("each PUT is the whole site with the master list, not a fragment",
        puts["sites/s1"]["keyExchangeAlgorithms"] == MASTER_KEX and puts["sites/s1"]["name"] == "PartnerOne" and puts["sites/s1"]["account"] == "john",
        puts.get("sites/s1"))

r = run_example.run(SCRIPT, ["--apply"], dict(world(sites=SITES), fail={"kind": "status:500", "on": "after_login", "method": "PUT"}))
c.check("a PUT the server answers 500 is not reported as done", "Successfully" not in r.output, r.output[-300:])
c.check("and the exit code is 1", r.returncode == 1, r.returncode)
r = run_example.run(SCRIPT, ["--yes"], world(sites=SITES))
c.check("an argument it does not know is exit 2, nothing sent", r.returncode == 2 and r.calls == [], r.returncode)
failures += 0 if c.summary() else 1

# ============================================================ stUpdateAllAccounts.py
print()
c = fake_st.Checker("stUpdateAllAccounts.py: a dry run by default, a certificate found from the script, not from the current directory")
SCRIPT = "stUpdateAllAccounts.py"
PEM = {"python3/ST_API_client.pem": "not a real key"}
accounts = USERS + [{"id": "a8", "name": "templateTwo", "type": "template"}]
r = run_example.run(SCRIPT, [], world(accounts=accounts), tree_files=PEM)
c.check("with no argument it changes nothing: exit 0, no PATCH", r.returncode == 0 and r.writes() == [], (r.returncode, r.writes()))
c.check("it says what it would send", "DRY RUN" in r.output and "ZZtemplate" in r.output and "templateTwo" in r.output, r.output)

r = run_example.run(SCRIPT, ["--apply"], world(accounts=accounts), tree_files=PEM)
patches = {e["path"]: e["body"] for e in r.writes() if e["method"] == "PATCH"}
c.check("--apply patches the template accounts only, though the script was started in another directory",
        sorted(patches) == ["accounts/ZZtemplate", "accounts/templateTwo"], (sorted(patches), r.returncode, r.output[-300:]))
c.check("replace where the field is there, add where it is not",
        patches["accounts/ZZtemplate"][0]["op"] == "replace" and patches["accounts/templateTwo"][0]["op"] == "add", patches)
c.check("it listed template accounts, with type=template", any(e["query"].get("type") == "template" for e in r.calls if e["path"] == "accounts"))
c.check("the login sent the client certificate, not a password",
        not any(e.get("violation") for e in r.calls), r.violations())

r = run_example.run(SCRIPT, ["--apply"], world(accounts=accounts))
c.check("no certificate: exit 1 and nothing sent", r.returncode == 1 and r.calls == [] and "client certificate" in r.output, (r.returncode, r.output[-300:]))
r = run_example.run(SCRIPT, ["--apply"], world(accounts=accounts), config={"st_client_cert": "mine/client.pem"},
                    tree_files={"mine/client.pem": "not a real key"})
c.check("st_client_cert in the config names it, relative to the config", r.returncode == 0 and len(r.writes()) == 2, (r.returncode, r.output[-300:]))

r = run_example.run(SCRIPT, ["--apply"], dict(world(accounts=accounts), fail={"kind": "status:500", "on": "after_login", "method": "PATCH"}), tree_files=PEM)
c.check("a PATCH the server answers 500 is not reported as updated, and the exit code is 1",
        "Updated account" not in r.output and r.returncode == 1, (r.returncode, r.output[-300:]))
failures += 0 if c.summary() else 1

# ===================================== the bulk scripts that already had a dry run
print()
c = fake_st.Checker("stUpdateAllRoutes.py, stUpdateAllSubscriptions.py, stUpdateRouteWithPut.py: a dry run unless --apply, a refused write is exit 1")
for script, args, scenario in (("stUpdateAllRoutes.py", [], world(routes=fixture("routes.json"))),
                               ("stUpdateAllSubscriptions.py", [], world(subscriptions=SUBSCRIPTIONS)),
                               ("stUpdateRouteWithPut.py", ["c1"], world(routes=[fixture("composite_route.json")]))):
    r = run_example.run(script, args, scenario)
    c.check("%s: with no --apply it writes nothing" % script, r.returncode == 0 and r.writes() == [] and "DRY RUN" in r.output,
            (r.returncode, r.writes()[:1], r.output[-200:]))
    verb = "PUT" if "WithPut" in script else "PATCH"
    r = run_example.run(script, ["--apply"] + args, dict(scenario, fail={"kind": "status:500", "on": "after_login", "method": verb}))
    c.check("%s: a %s the server answers 500 is exit 1" % (script, verb), r.returncode == 1, (r.returncode, r.output[-200:]))
r = run_example.run("stUpdateAllRoutes.py", ["--bogus"], world(routes=[]))
c.check("an unknown argument is exit 2, nothing sent", r.returncode == 2 and r.calls == [], r.returncode)
r = run_example.run("stUpdateRouteWithPut.py", [], world(routes=[]))
c.check("stUpdateRouteWithPut.py: no route id is exit 2, nothing sent", r.returncode == 2 and r.calls == [], r.returncode)
r = run_example.run("stUpdateRouteWithPut.py", ["--apply", "c1"], world(routes=[fixture("composite_route.json")]),
                    edits={"insertAtOffset = 0": "insertAtOffset = 99"})
c.check("stUpdateRouteWithPut.py: an insert offset outside the route is exit 1, no PUT", r.returncode == 1 and r.writes() == [], (r.returncode, r.writes()))
failures += 0 if c.summary() else 1

# ================================================================= stConfigScan.py
print()
c = fake_st.Checker("stConfigScan.py: a JSON baseline, in both directions, with a path that is not hard coded")
SCRIPT = "stConfigScan.py"
live = world(**{"configurations/options": OPTIONS})
r = run_example.run(SCRIPT, ["MAKEBASELINE", "base.json"], live)
written = r.read("base.json")
c.check("MAKEBASELINE writes the baseline where it is told", r.returncode == 0 and written is not None, (r.returncode, r.output[-300:]))
c.check("it is JSON, option name to values (a pickle would run code when it is read back)",
        written is not None and json.loads(written) == {"A.One": ["1"], "B.Two": ["2"], "D.Four": ["4"]}, written)
c.check("and readable by its owner only", r.mode("base.json") == 0o600, oct(r.mode("base.json") or 0))

r = run_example.run(SCRIPT, ["MAKEBASELINE"], live)
c.check("with no path it writes stConfig.baseline next to the script, not /home/axway", r.read("stConfig.baseline", "script") is not None
        and "/home/axway" not in r.output, r.output[-300:])
r = run_example.run(SCRIPT, ["MAKEBASELINE"], live, config={"st_config_baseline": "elsewhere.json"})
c.check("st_config_baseline in the config sets the path", r.returncode == 0 and "elsewhere.json" in r.output, r.output[-300:])

baseline = {"A.One": ["1"], "B.Two": ["old"], "C.Three": ["3"]}
r = run_example.run(SCRIPT, ["COMPAREBASELINE", "base.json"], live, files={"base.json": json.dumps(baseline)})
c.check("COMPAREBASELINE reports a value that changed", "B.Two has changed from ['old']  to ['2']" in r.output, r.output)
c.check("an option that is new on the live system", "D.Four" in r.output and "does not exist in the baseline" in r.output, r.output)
c.check("and an option that is in the baseline and gone from the live system",
        "C.Three" in r.output and "in the baseline but not on the live system" in r.output, r.output)
c.check("it only reads: exit 0, no write", r.returncode == 0 and r.writes() == [], (r.returncode, r.writes()))
r = run_example.run(SCRIPT, ["COMPAREBASELINE", "base.json"], live, files={"base.json": json.dumps({k: v for k, v in
                    ((o["name"], o["values"]) for o in OPTIONS)})})
c.check("no difference: it says none", "Differences: 0 changed, 0 new, 0 gone" in r.output and r.returncode == 0, r.output[-300:])

r = run_example.run(SCRIPT, ["COMPAREBASELINE", "old.pickle"], live, files={"old.pickle": b"\x80\x04N."})
c.check("a baseline that is not JSON (a pickle) is refused, exit 1, and not loaded", r.returncode == 1 and "not JSON" in r.output, (r.returncode, r.output[-300:]))
r = run_example.run(SCRIPT, ["COMPAREBASELINE", "missing.json"], live)
c.check("no baseline to compare with: exit 1, and the server was not asked", r.returncode == 1 and r.calls == [], (r.returncode, r.calls[:1]))
r = run_example.run(SCRIPT, ["COMPAREBASELINE", "list.json"], live, files={"list.json": "[1, 2]"})
c.check("a baseline that is not a set of options is refused, exit 1", r.returncode == 1, (r.returncode, r.output[-200:]))
for mode in ("XMAKEBASELINEX", "makebaseline", "MAKEBASELINE,COMPAREBASELINE", ""):
    r = run_example.run(SCRIPT, [mode], live)
    c.check("the mode %r is not accepted: exit 2, nothing sent" % mode, r.returncode == 2 and r.calls == [], (r.returncode, r.calls[:1]))
r = run_example.run(SCRIPT, [], live)
c.check("no mode: exit 2", r.returncode == 2, r.returncode)
many = [{"name": "Opt.%03d" % i, "values": [str(i)]} for i in range(250)]
r = run_example.run(SCRIPT, ["MAKEBASELINE", "big.json"], world(**{"configurations/options": many}))
c.check("over several pages it keeps every option", len(json.loads(r.read("big.json") or b"{}")) == 250, r.output[-200:])
failures += 0 if c.summary() else 1

# ============================================================== stGetPrivateCert.py
print()
c = fake_st.Checker("stGetPrivateCert.py: the password out of the URL and the output, the key file private")
SCRIPT = "stGetPrivateCert.py"
PASSWORD = "Pw_for_the_test_1"
r = run_example.run(SCRIPT, ["c1"], world(certificates=CERTIFICATES), env={"ST_EXPORT_PASSWORD": PASSWORD})
export = [e for e in r.calls if "operations" in e["path"]]
c.check("exit 0", r.returncode == 0, (r.returncode, r.output[-300:]))
c.check("it asks the export operation of the reference, as pkcs12",
        len(export) == 1 and export[0]["method"] == "POST" and export[0]["query"].get("operation") == "export"
        and export[0]["query"].get("format") == "pkcs12", export)
c.check("the password is a form field of the body, not in any URL", export and export[0]["files"] == ["exportPassword"]
        and all(PASSWORD not in e["url"] for e in r.calls), [e["url"] for e in r.calls])
c.check("the password is not printed", PASSWORD not in r.output and "12345678" not in r.output, r.output)
c.check("the key is written to exportedPrivateKey.p12", r.read("exportedPrivateKey.p12") is not None)
c.check("readable by its owner only (0600)", r.mode("exportedPrivateKey.p12") == 0o600, oct(r.mode("exportedPrivateKey.p12") or 0))

r = run_example.run(SCRIPT, ["c1", "mykey.p12"], world(certificates=CERTIFICATES), env={"ST_EXPORT_PASSWORD": PASSWORD})
c.check("the output file is the second argument", r.read("mykey.p12") is not None and r.mode("mykey.p12") == 0o600, r.output[-200:])
r = run_example.run(SCRIPT, ["c1", "mykey.p12"], world(certificates=CERTIFICATES), env={"ST_EXPORT_PASSWORD": PASSWORD},
                    files={"mykey.p12": "do not overwrite me"})
c.check("a file that is there is never written over: exit 1, and the server is not asked",
        r.returncode == 1 and r.read("mykey.p12") == b"do not overwrite me" and r.calls == [], (r.returncode, r.calls[:1]))
r = run_example.run(SCRIPT, ["c1"], world(certificates=CERTIFICATES))
c.check("with no password, in the environment or at a prompt, it asks nothing of the server: exit 2",
        r.returncode == 2 and r.calls == [] and r.read("exportedPrivateKey.p12") is None, (r.returncode, r.calls[:1]))
r = run_example.run(SCRIPT, [], world(certificates=CERTIFICATES), env={"ST_EXPORT_PASSWORD": PASSWORD})
c.check("no certificate id: exit 2", r.returncode == 2 and r.calls == [], r.returncode)
r = run_example.run(SCRIPT, ["nope"], world(certificates=CERTIFICATES), env={"ST_EXPORT_PASSWORD": PASSWORD})
c.check("a certificate the server does not have: exit 1, and no key file left", r.returncode == 1 and r.read("exportedPrivateKey.p12") is None,
        (r.returncode, r.output[-200:]))
gi = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".gitignore")).read().split("\n")
c.check("the key file name and the baseline are in .gitignore", "exportedPrivateKey*" in gi and "*.baseline" in gi, [g for g in gi if "xported" in g or "baseline" in g])
failures += 0 if c.summary() else 1

# ============================================================== stAddLoginRestrictionRule.py
print()
c = fake_st.Checker("stAddLoginRestrictionRule.py: the rule goes in once, at the end, with the csrfToken")
SCRIPT = "stAddLoginRestrictionRule.py"
policy = {"id": "p1", "name": "ZZ_policy", "type": "ALLOW_THEN_DENY",
          "rules": [{"name": "first", "type": "DENY"}, {"name": "second", "type": "DENY"}]}
r = run_example.run(SCRIPT, ["ZZ_policy"], world(loginRestrictionPolicies=[policy]))
patch = [e for e in r.writes() if e["method"] == "PATCH"]
c.check("one PATCH, adding the rule at the index that is the number of rules now there",
        len(patch) == 1 and patch[0]["body"][0]["path"] == "/rules/2" and patch[0]["body"][0]["value"]["name"] == "sessions fewer than 4", patch)
c.check("with the csrfToken, and no refusal", patch and patch[0]["has_csrf"] and r.violations() == [] and r.returncode == 0, (r.violations(), r.returncode))
exists = dict(policy, rules=[{"name": "sessions fewer than 4", "type": "ALLOW"}])
r = run_example.run(SCRIPT, ["ZZ_policy"], world(loginRestrictionPolicies=[exists]))
c.check("a rule of that name is there already: nothing is sent, exit 0, and it logs out",
        r.returncode == 0 and r.writes() == [] and any(e["method"] == "DELETE" and e["path"] == "myself" for e in r.calls),
        (r.returncode, r.writes()))
r = run_example.run(SCRIPT, ["NoSuchPolicy"], world(loginRestrictionPolicies=[policy]))
c.check("a policy that is not there: exit 1, no write", r.returncode == 1 and r.writes() == [], (r.returncode, r.writes()))
r = run_example.run(SCRIPT, [], world(loginRestrictionPolicies=[policy]))
c.check("no policy name: exit 2, nothing sent", r.returncode == 2 and r.calls == [], r.returncode)
failures += 0 if c.summary() else 1

# ===================================================== the Expression Language examples
print()
c = fake_st.Checker("14.ExpressionLanguage: clean up what the run created, and nothing else, even when it fails")
EL = "14.ExpressionLanguage/"

r = run_example.run(EL + "01.loginRestrictionPolicy_sessionExpression.py", [],
                    world(loginRestrictionPolicies=[{"id": "pre", "name": "ZZTEST_EL_sessionLimit", "type": "ALLOW_THEN_DENY", "rules": []}]))
c.check("01: a policy of that name is there already: the POST is refused, so exit 1", r.returncode == 1, (r.returncode, r.output[-200:]))
c.check("01: and the policy that was there is not changed or deleted", [(e["method"]) for e in r.writes()] == ["POST"],
        [(e["method"], e["path"]) for e in r.writes()])

old_routes = [{"id": "old%d" % i, "name": "ZZTEST_EL_route_disabled", "type": "SIMPLE"} for i in range(2)]
r = run_example.run(EL + "02.routes_condition_EL.py", [], world(routes=old_routes))
deleted = sorted(e["path"] for e in r.writes() if e["method"] == "DELETE")
created = [e for e in r.writes() if e["method"] == "POST"]
c.check("02: routes of the same names are there already (route names may repeat): three more are made", len(created) == 3, len(created))
c.check("02: only the three it created are deleted, by id: the two that were there are not",
        len(deleted) == 3 and not any(d in ("routes/old0", "routes/old1") for d in deleted), deleted)

for script, label in (("07.transferSites_downloadPattern.py", "ZZTEST_EL_dlpattern_anyXml"), ("08.transferSites_dynamicProperties.py", "ZZTEST_EL_dynamicSite")):
    r = run_example.run(EL + script, [], world(sites=[{"id": "pre", "name": label, "protocol": "ssh"}]))
    c.check("%s: a site of that name is there already: exit 1, and nothing is deleted" % script[:2],
            r.returncode == 1 and not [e for e in r.writes() if e["method"] == "DELETE"], (r.returncode, [(e["method"], e["path"]) for e in r.writes()]))

for script in ("02.routes_condition_EL.py", "03.routes_step_fileFilterExpression_glob.py", "06.routes_step_renameExpression.py",
               "07.transferSites_downloadPattern.py", "01.loginRestrictionPolicy_sessionExpression.py"):
    r = run_example.run(EL + script, [], dict(world(), fail={"kind": "status:500", "on": "after_login", "method": "GET"}))
    posts = [e for e in r.writes() if e["method"] == "POST"]
    deletes = [e for e in r.writes() if e["method"] == "DELETE"]
    c.check("%s: the read after the create fails (500): exit 1, and what was created is still deleted" % script[:2],
            r.returncode == 1 and len(posts) >= 1 and len(posts) == len(deletes), (r.returncode, len(posts), len(deletes)))
    r = run_example.run(EL + script, [], dict(world(), fail={"kind": "raise:Timeout", "on": "after_login", "method": "GET"}))
    posts = [e for e in r.writes() if e["method"] == "POST"]
    deletes = [e for e in r.writes() if e["method"] == "DELETE"]
    c.check("%s: the read times out: exit 1, no traceback, and what was created is still deleted" % script[:2],
            r.returncode == 1 and "Traceback" not in r.output and len(posts) == len(deletes) >= 1, (r.returncode, len(posts), len(deletes)))

r = run_example.run(EL + "02.routes_condition_EL.py", [], dict(world(), fail={"kind": "status:500", "on": "after_login", "method": "DELETE", "path": "routes/"}))
c.check("02: a delete the server refuses is exit 1, and says which object is left", r.returncode == 1 and "COULD NOT DELETE" in r.output,
        (r.returncode, r.output[-300:]))
r = run_example.run(EL + "02.routes_condition_EL.py", [], dict(world(), fail={"kind": "status:500", "on": "after_login", "method": "POST", "path": "routes"}))
c.check("02: a create the server refuses stops the script: exit 1, and no route is deleted that was not made",
        r.returncode == 1 and not [e for e in r.writes() if e["method"] == "DELETE"], (r.returncode, [(e["method"], e["path"]) for e in r.writes()]))
failures += 0 if c.summary() else 1

# ============================================================================== utils
print()
c = fake_st.Checker("python/utils: the exit codes, and the one that talks to a server")
UTILS = "../utils/"
XML = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures")
r = run_example.run(UTILS + "stCompareExportedConfigurations.py", [], world())
c.check("compare with no file names: exit 2", r.returncode == 2 and "Usage" in r.output, (r.returncode, r.output))
r = run_example.run(UTILS + "stCompareExportedConfigurations.py", ["a.xml"], world())
c.check("compare with one file name: exit 2", r.returncode == 2, r.returncode)
r = run_example.run(UTILS + "stCompareExportedConfigurations.py", ["missing.xml", "missing2.xml"], world())
c.check("compare with a file that is not there: exit 1, no traceback", r.returncode == 1 and "Traceback" not in r.output, (r.returncode, r.output[-200:]))
r = run_example.run(UTILS + "processSystemConfig.py", [], world())
c.check("processSystemConfig with no file name: exit 2", r.returncode == 2, r.returncode)

userclasses = open(os.path.join(XML, "userclasses.xml")).read()
r = run_example.run(UTILS + "processSystemConfig.py", ["uc.xml"], world(), files={"uc.xml": userclasses})
c.check("processSystemConfig converts and sends nothing by default: exit 0, no call", r.returncode == 0 and r.calls == [], (r.returncode, r.calls[:1]))
turn_on = {"createOnTarget = False": "createOnTarget = True"}
r = run_example.run(UTILS + "processSystemConfig.py", ["uc.xml"], world(), files={"uc.xml": userclasses}, edits=turn_on)
c.check("with createOnTarget True it creates the user classes, the csrfToken on every write, and exits 0",
        r.returncode == 0 and len([e for e in r.writes() if e["path"] == "userClasses"]) == 3 and r.violations() == [],
        (r.returncode, r.violations(), r.output[-300:]))
r = run_example.run(UTILS + "processSystemConfig.py", ["uc.xml"], dict(world(), fail={"kind": "status:500", "on": "after_login", "method": "POST", "path": "userClasses"}),
                    files={"uc.xml": userclasses}, edits=turn_on)
c.check("user classes the server refuses make the exit code 1", r.returncode == 1, (r.returncode, r.output[-200:]))
for label, fail in (("a connection error", {"kind": "raise:ConnectionError"}), ("a timeout after the login", {"kind": "raise:Timeout", "on": "after_login"}),
                    ("the login refused", {"kind": "status:401", "on": "login"})):
    r = run_example.run(UTILS + "processSystemConfig.py", ["uc.xml"], dict(world(), fail=fail), files={"uc.xml": userclasses}, edits=turn_on)
    c.check("processSystemConfig, %s: exit 1, no traceback" % label, r.returncode == 1 and "Traceback" not in r.output, (r.returncode, r.output[-200:]))
failures += 0 if c.summary() else 1

# ================================================== usage, config and the date: exit codes
print()
c = fake_st.Checker("a missing config, a missing argument and a bad one: non-zero, and nothing sent")
NEEDS_ARG = (("stGetAccountsAfterDate.py", []), ("stGetAccountsAfterDate.py", ["01/02/2024"]), ("stGetAccountsAfterDate.py", ["2024-13-45"]),
             ("stBillableTransfers.py", ["0"]), ("stBillableTransfers.py", ["many"]), ("stCertificateExpiry.py", ["soon"]),
             ("stConfigScan.py", []), ("stGetPrivateCert.py", []), ("stAddLoginRestrictionRule.py", []),
             ("stUpdateRouteWithPut.py", []), ("stGraceful.py", []))
for script, args in NEEDS_ARG:
    r = run_example.run(script, args, world())
    c.check("%s %s: exit 2, nothing sent" % (script, args), r.returncode == 2 and r.calls == [] and "Traceback" not in r.output,
            (r.returncode, r.output[-200:]))
ALL = ("stAddLoginRestrictionRule.py ZZ_policy", "stBillableTransfers.py", "stBuildFullTestAccount.py", "stBuildTestAccounts.py --apply",
       "stCertificateExpiry.py", "stConfigScan.py MAKEBASELINE", "stDeleteTestAccounts.py --apply", "stGetAccountsAfterDate.py 2000-01-01",
       "stGetPrivateCert.py c1", "stGraceful.py 30 --yes", "stReplaceSites.py --apply", "stUpdateAllAccounts.py --apply",
       "stUpdateAllRoutes.py --apply", "stUpdateAllSubscriptions.py --apply", "stUpdateRouteWithPut.py --apply c1",
       "stUsersPerSharedFolder.py")
for spec in ALL:
    script, args = spec.split()[0], spec.split()[1:]
    for label, config in (("no config file", False),
                          ("a config with no password", {"st_password": None}),
                          ("a config with no server", {"st_server": None})):
        r = run_example.run(script, args, world(), config=config, env={"ST_EXPORT_PASSWORD": "Pw_for_the_test_1"})
        c.check("%s, %s: exit 1, nothing sent, no traceback" % (script, label),
                r.returncode == 1 and r.calls == [] and "Traceback" not in r.output and "configuration" in r.output,
                (r.returncode, r.output[-200:]))
failures += 0 if c.summary() else 1

print()
if failures:
    print("test_python_safety: FAIL (%d group(s))" % failures)
    sys.exit(1)
print("test_python_safety: PASS")
