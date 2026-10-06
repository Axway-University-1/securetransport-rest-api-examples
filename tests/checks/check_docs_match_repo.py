#!/usr/bin/env python3
"""
Check that the documentation still describes the repository it ships with.

The README coverage tables and the .claude skills both cite counts, paths and
variable names. Documentation that has quietly drifted is worse than none, so
this check compares every citable claim against the filesystem.

Runs offline. Exit code 0 means clean.
"""
import glob
import os
import re
import subprocess
import sys

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
REPO = os.path.abspath(REPO)

failed = 0


def chk(label, condition, detail=""):
    global failed
    if condition:
        print("  PASS  " + label)
    else:
        failed += 1
        print("  FAIL  " + label + (("  got: " + str(detail)) if detail else ""))


def tracked():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=REPO,
                         capture_output=True, text=True).stdout
    return [f for f in out.split("\0") if f]


def count(path, ext):
    full = os.path.join(REPO, path)
    if not os.path.isdir(full):
        return 0
    return len([f for f in os.listdir(full) if f.endswith(ext)])


README = open(os.path.join(REPO, "README.md")).read()

# ----------------------------------------------------------- README coverage
print("=== README coverage tables match the directories ===")

A, B = "Admin/API 2.0/bash", "Admin/API 2.0/bat"
rows = [("01. Authentication", "01.Authentication"),
        ("02. Introduction", "02.Introduction"),
        ("03. Connect", "03.Connect"),
        ("04. Applications", "04.Applications"),
        ("05. Accounts", "05.Accounts"),
        ("06. Transfer Sites", "06.TransferSites"),
        ("07. Subscriptions", "07.Subscriptions"),
        ("08. Route Templates", "08.RouteTemplates"),
        ("09. Composite Routes", "09.CompositeRoutes"),
        ("12. Business Units", "12.BusinessUnits"),
        ("13. Configurations", "13.Configurations"),
        ("15. Transfers", "15.Transfers"),
        ("16. Transfer Logs", "16.TransferLogs"),
        ("17. Access Policies", "17.AccessPolicies"),
        ("18. Account Setup", "18.AccountSetup"),
        ("19. Address Book", "19.AddressBook"),
        ("20. Administrative Roles", "20.AdministrativeRoles"),
        ("21. Administrators", "21.Administrators"),
        ("90. End To End Acknowledgment", "90.EndToEndAcknowledgment")]

for label, folder in rows:
    sh, bat = count(A + "/" + folder, ".sh"), count(B + "/" + folder, ".bat")
    m = re.search(r"^\| %s \| [^|]*\| *(\S+) *\| *(\S+) *\|" % re.escape(label),
                  README, re.M)
    if not m:
        chk("row present: " + label, False)
        continue
    chk("%s  %s/%s" % (label, sh, bat), (m.group(1), m.group(2)) == (str(sh), str(bat)),
        "%s/%s in README" % (m.group(1), m.group(2)))

for label, folder in (("01. Authenticate", "01.Authenticate"), ("02. Files", "02.Files"),
                      ("03. Myself", "03.Myself"), ("04. File Operations", "04.FileOperations"),
                      ("05. Transfers", "05.Transfers"), ("06. Server Time", "06.ServerTime")):
    n = str(count("EndUser/API 2.0/bash/" + folder, ".sh"))
    m = re.search(r"^\| %s \| [^|]*\| *(\S+) *\|" % re.escape(label), README, re.M)
    chk("EndUser %s  %s" % (label, n), bool(m) and m.group(1) == n,
        m.group(1) if m else None)

# --------------------------------------------------- every named script exists
print()
print("=== every python script the README names exists ===")
named = set(re.findall(r"`(?:python3/)?(st[A-Za-z]+\.py|processSystemConfig\.py)`", README))
have = set(os.path.basename(p) for p in
           glob.glob(os.path.join(REPO, "Admin/API 2.0/python/python3/*.py")) +
           glob.glob(os.path.join(REPO, "Admin/API 2.0/python/utils/*.py")))
for n in sorted(named):
    chk("named and present: " + n, n in have)
undocumented = sorted(have - named)
chk("no python script is undocumented", not undocumented, ", ".join(undocumented))

# ------------------------------------------------------------ knowledge pack
print()
print("=== the .claude skills still describe this repository ===")

pack = glob.glob(os.path.join(REPO, ".claude/skills/*/SKILL.md")) + \
       glob.glob(os.path.join(REPO, ".claude/agents/*.md"))
chk("the knowledge pack is present", len(pack) == 4, len(pack))

for p in pack:
    text = open(p).read()
    rel = os.path.relpath(p, REPO)
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        chk(rel + ": has frontmatter", False)
        continue
    fm = dict(re.findall(r"^([a-z]+):\s*(.+)$", m.group(1), re.M))
    slug = os.path.basename(os.path.dirname(p)) if p.endswith("SKILL.md") \
        else os.path.basename(p)[:-3]
    chk(rel + ": name matches its location", fm.get("name") == slug, fm.get("name"))
    chk(rel + ": has a description", bool(fm.get("description")))

pack_text = "\n".join(open(p).read() for p in pack)

n_bash = len([f for f in tracked() if re.match(r"Admin/API 2\.0/bash/[^/]+/.*\.sh$", f)])
n_bat = len([f for f in tracked() if re.match(r"Admin/API 2\.0/bat/[^/]+/.*\.bat$", f)])
n_eu = len([f for f in tracked() if re.match(r"EndUser/API 2\.0/bash/[^/]+/.*\.sh$", f)])
n_p3 = count("Admin/API 2.0/python/python3", ".py")
n_ut = count("Admin/API 2.0/python/utils", ".py")

for n, what in ((n_bash, "bash"), (n_bat, "bat")):
    chk("pack cites %d %s examples" % (n, what), ("%d %s examples" % (n, what)) in pack_text
        or ("%d curl examples" % n) in pack_text or ("the same %d" % n) in pack_text)
chk("pack cites %d enduser examples" % n_eu, str(n_eu) + " examples" in pack_text)
chk("pack cites %d python3 scripts" % n_p3, str(n_p3) + " complete programs" in pack_text)
chk("pack cites %d utils tools" % n_ut, str(n_ut) + " tools" in pack_text)

# Files the pack points people at
for cited in re.findall(r"`((?:bash|bat|python3|utils)/[A-Za-z0-9_./-]+\.(?:sh|bat|py))`", pack_text):
    found = any(os.path.exists(os.path.join(REPO, pre + cited))
                for pre in ("Admin/API 2.0/", "Admin/API 2.0/python/"))
    chk("pack cites a real file: " + cited, found)

# The configuration contract the pack documents
sv = open(os.path.join(REPO, "Admin/API 2.0/bash/set_variables.sh")).read()
chk("the four ST_ variables are exported",
    all(("export " + v) in sv for v in ("ST_SERVER", "ST_PORT", "ST_USER", "ST_PASSWORD")))
chk("PWD is not used as a password variable", "export PWD=" not in sv)

eu = open(os.path.join(REPO, "EndUser/API 2.0/bash/set_variables.sh")).read()
chk("EndUser derives ST_URL and ST_BASIC_AUTH", "ST_URL=" in eu and "ST_BASIC_AUTH=" in eu)

for f in ("Admin/API 2.0/bash/set_variables.local.example.sh",
          "Admin/API 2.0/bat/set_variables.local.example.bat",
          "Admin/API 2.0/python/config.example",
          "EndUser/API 2.0/bash/set_variables.local.example.sh"):
    chk("example config committed: " + os.path.basename(f), f in tracked())

dry = [os.path.basename(p) for p in
       glob.glob(os.path.join(REPO, "Admin/API 2.0/python/**/*.py"), recursive=True)
       if "dryRun = True" in open(p).read() or "createOnTarget = False" in open(p).read()]
chk("4 scripts default to a dry run", len(dry) == 4, sorted(dry))

print()
if failed:
    print("check_docs_match_repo: FAIL (%d)" % failed)
    sys.exit(1)
print("check_docs_match_repo: PASS")
