#!/usr/bin/env python3
"""
Every python example says how much it can change on the server, in a 'Risk:' line of
its header, with the same four levels as the bash and bat examples (read, write, config,
disruptive). check_risk_headers.py holds the bash and bat examples to it; this holds the
python ones, which tools/list_examples.py does not list.

The helper el_client.py is not an example (the Expression Language scripts import it),
so it is not held to this.

Runs offline. Exit code 0 means clean.
"""
import glob
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools"))
import list_examples as le  # noqa: E402

failed = 0


def chk(label, condition, detail=""):
    global failed
    if condition:
        print("  PASS  " + label)
    else:
        failed += 1
        print("  FAIL  " + label + (("  got: " + str(detail)) if detail else ""))


def python_examples():
    base = os.path.join(REPO, "Admin", "API 2.0", "python")
    found = (glob.glob(os.path.join(base, "python3", "*.py"))
             + glob.glob(os.path.join(base, "python3", "14.ExpressionLanguage", "*.py"))
             + glob.glob(os.path.join(base, "utils", "*.py")))
    return sorted(p for p in found if os.path.basename(p) != "el_client.py")


files = python_examples()
chk("the python examples are found (16 programs, 8 Expression Language exercises, 2 tools)", len(files) == 26, len(files))

levels = {}
for path in files:
    rel = os.path.relpath(path, REPO)
    text = open(path).read()
    lines = [l for l in text.split("\n") if re.match(r"^# Risk:", l)]
    chk("%s: exactly one Risk line" % rel, len(lines) == 1, lines)
    level, note = le.risk_of(text)
    chk("%s: the level is one of read, write, config, disruptive" % rel, level in le.LEVELS, level)
    levels[os.path.basename(path)] = (level, note)
    if level and level != "read":
        chk("%s: a level that is not read says why" % rel, bool(note and note.strip()), note)

# what the examples are known to do, so a level cannot drift away from it
chk("stGraceful.py is the one disruptive example", [n for n, (l, _) in levels.items() if l == "disruptive"] == ["stGraceful.py"],
    [n for n, (l, _) in levels.items() if l == "disruptive"])
chk("the examples that only read are read",
    all(levels.get(n, (None,))[0] == "read" for n in (
        "stBillableTransfers.py", "stCertificateExpiry.py", "stConfigScan.py", "stGetAccountsAfterDate.py",
        "stGetPrivateCert.py", "stUsersPerSharedFolder.py", "stCompareExportedConfigurations.py")),
    {n: levels.get(n) for n in ("stBillableTransfers.py", "stCertificateExpiry.py", "stConfigScan.py", "stGetAccountsAfterDate.py",
                                "stGetPrivateCert.py", "stUsersPerSharedFolder.py")})
chk("the examples that create, change or delete objects are write",
    all(levels.get(n, (None,))[0] == "write" for n in (
        "stAddLoginRestrictionRule.py", "stBuildFullTestAccount.py", "stBuildTestAccounts.py", "stDeleteTestAccounts.py",
        "stReplaceSites.py", "stUpdateAllAccounts.py", "stUpdateAllRoutes.py", "stUpdateAllSubscriptions.py",
        "stUpdateRouteWithPut.py", "processSystemConfig.py")))
chk("every Expression Language exercise is write",
    all(l == "write" for n, (l, _) in levels.items() if re.match(r"^\d\d\.", n)),
    {n: l for n, (l, _) in levels.items() if re.match(r"^\d\d\.", n)})
chk("stGetPrivateCert.py says it writes a private key to disk, though it only reads the server",
    "private key" in (levels.get("stGetPrivateCert.py") or ("", ""))[1], levels.get("stGetPrivateCert.py"))

# what a script does to the server must not be more than it says: a read has no PATCH or PUT in it
for path in files:
    level = levels[os.path.basename(path)][0]
    if level == "read":
        code = "\n".join(l for l in open(path).read().split("\n") if not l.lstrip().startswith("#"))
        chk("%s: a read does not PATCH or PUT" % os.path.relpath(path, REPO),
            not re.search(r"""(\.patch\(|\.put\(|['"](PATCH|PUT)['"])""", code))

# the claim the README makes
readme = open(os.path.join(REPO, "README.md")).read()
chk("the README says the python examples carry a Risk line too", re.search(r"python.{0,80}Risk|Risk.{0,160}python", readme, re.S) is not None)

print()
if failed:
    print("check_python_risk: FAIL (%d)" % failed)
    sys.exit(1)
print("check_python_risk: PASS")
