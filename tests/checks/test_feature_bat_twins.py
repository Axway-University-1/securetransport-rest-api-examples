#!/usr/bin/env python3
"""
Check that each Features .bat twin carries the same API content as its .sh.

The .bat files cannot be run in this repository's test environment, so this is the
safety net: every API field name (a camelCase word such as postTransmissionActions)
and every AR_ setting that a .sh file uses must also appear in its .bat twin, and the
other way round. Comments are ignored.

A name that really differs by design (a bash-only helper variable) goes in
ALLOWED_DIFFERENCES below, with the reason.

Runs offline. Exit code 0 means clean.
"""
import os
import re
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FEATURES = os.path.join(REPO, "Features")

# Names that legitimately differ between the two languages
ALLOWED_DIFFERENCES = {
    "triggerName",   # a jq --arg name in the bash version; PowerShell reads the environment
    "AR_EU_URL", "AR_EU_BODY", "AR_EU_CODE", "AR_EU_CSRF", "AR_EU_JAR",  # bash helper state; bat uses EU_*
    "AR_STATE_FILE",  # bash helper path; bat writes state.local.bat directly
}

failed = 0


def check(label, ok, detail=""):
    global failed
    if ok:
        print("  PASS  " + label)
    else:
        failed += 1
        print("  FAIL  " + label + (("  " + detail) if detail else ""))


def tokens(path):
    text = open(path).read()
    code = "\n".join(l for l in text.split("\n") if not re.match(r"\s*(#|REM\b)", l))
    words = set(re.findall(r"\b[a-z]+[A-Z][A-Za-z]+\b", code))
    words |= set(re.findall(r"\bAR_[A-Z_]+\b", code))
    # An escaped newline in a format string looks like a word: \nHTTP, \nAll
    words = {w for w in words if not re.match(r"^n[A-Z]", w)}
    return words - ALLOWED_DIFFERENCES


print("=== Each .sh in Features has a .bat with the same API content ===")
pairs = 0
# Tracked files only: a developer's own settings.local.sh or state.local.sh is not part
# of the repository and has no twin
tracked = subprocess.run(["git", "ls-files", "Features/*.sh"], cwd=REPO,
                         capture_output=True, text=True).stdout.split()
for sh in sorted(os.path.join(REPO, f) for f in tracked):
    bat = sh[:-3] + ".bat"
    name = os.path.relpath(sh, REPO)
    if not os.path.exists(bat):
        check(name, False, "has no .bat twin")
        continue
    pairs += 1
    only_sh = tokens(sh) - tokens(bat)
    only_bat = tokens(bat) - tokens(sh)
    check(name, not only_sh and not only_bat,
          "only in .sh: %s; only in .bat: %s" % (sorted(only_sh), sorted(only_bat)))

check("found the pairs to compare", pairs >= 15, "pairs: %d" % pairs)

print()
print("test_feature_bat_twins: " + ("PASS" if failed == 0 else "FAIL"))
sys.exit(1 if failed else 0)
