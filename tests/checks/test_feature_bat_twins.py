#!/usr/bin/env python3
"""
Check that each Features .bat twin carries the same API content as its .sh.

The .bat files cannot be run in this repository's test environment, so this is the
safety net: every API field name (a camelCase word such as postTransmissionActions)
and every SETTING_LIKE_THIS a .sh file uses must also appear in its .bat twin, and
the other way round. Comments are ignored.

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
    # bat's own enduser.bat implementation state (EU_JAR, EU_CODE, ...) - the bash side
    # calls these AR_EU_*, above. Only EU_ACCOUNT, EU_ACCOUNT_PASSWORD and EU_ENDUSER_PORT
    # (not listed here) are the actual cross-language contract: the neutral names each
    # feature's settings.sh/.bat alias its own prefix to, before enduser is loaded/called.
    "EU_JAR", "EU_CODE", "EU_CSRF", "EU_HEADERS", "EU_BODY_FILE",
    "AR_STATE_FILE",  # bash helper path; bat writes state.local.bat directly
    # A bat file SETs EU_ACCOUNT before it CALLs enduser.bat login, to log in as a
    # partner; bash calls bt_login_as ACCOUNT (settings.sh), which sets it
    "EU_ACCOUNT",
    # bash: the account ar_ensure_usable_home (lib/home_folder.sh) is on while it moves on to
    # the next name. A batch file cannot call back into the script that called it, so the same
    # loop is in each feature's 00.run_all.bat, on its own variables (PROBE_N, BT_RUN_ACCOUNT, ...)
    "AR_HOME_ACCOUNT",
}


def setting_prefixes():
    """Every feature's own settings prefix (AR, BT, ...), found from its settings.sh:
    whatever comes before the first underscore in an `export WHATEVER_NAME=` line.
    Generic on purpose, so a new feature's own prefix is picked up without editing
    this check."""
    prefixes = set()
    for root, _dirs, files in os.walk(FEATURES):
        if "settings.sh" in files:
            text = open(os.path.join(root, "settings.sh")).read()
            prefixes |= set(re.findall(r"^export\s+([A-Z][A-Z0-9]*)_[A-Z0-9_]+=", text, re.M))
    return prefixes


PREFIXES = setting_prefixes()

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
    # A setting from any feature's own prefix (AR_, BT_, ...), not implementation-only
    # all-caps locals a language forces on itself (PA_HEADERS, EU_CODE, SCRIPT_DIR, ...)
    if PREFIXES:
        words |= set(re.findall(r"\b(?:%s)_[A-Z0-9_]+\b" % "|".join(sorted(PREFIXES)), code))
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


# ------------------------------------------------------------------------------
# The .bat twins cannot run in this test environment, so what makes a refused call stop an
# example is checked in their source. The behaviour itself is in test_feature_trigger_route_pull.sh
# and test_feature_billable_transfers.sh, which run the .sh twins.
# ------------------------------------------------------------------------------
print()
print("=== A refused call stops the example: the .bat twins read the code of every call ===")


def code_lines(path):
    """The lines of a file that are not comments or empty, with their number"""
    out = []
    for n, line in enumerate(open(path, newline="").read().replace("\r\n", "\n").split("\n"), 1):
        if line.strip() and not re.match(r"\s*(REM\b|::)", line, re.I):
            out.append((n, line))
    return out


tracked_all = subprocess.run(["git", "ls-files", "Features"], cwd=REPO, capture_output=True, text=True).stdout.split()
steps_bat = sorted(f for f in tracked_all
                   if f.endswith(".bat") and "/lib/" not in f and not os.path.basename(f).startswith("settings"))
steps_sh = sorted(f for f in tracked_all
                  if f.endswith(".sh") and "/lib/" not in f and not os.path.basename(f).startswith("settings"))

# A CALL to the shared Admin helpers (post and delete: their ERRORLEVEL is 0 only for a 2xx; exists
# says 0, 1 or 2) must be followed by a line that reads ERRORLEVEL, before anything else can reset it
needs_check = re.compile(r'post_admin\.bat"|admin_calls\.bat"\s+(delete|exists)', re.I)
unchecked = []
for rel in steps_bat:
    lines = code_lines(os.path.join(REPO, rel))
    for i, (n, line) in enumerate(lines):
        if re.match(r"\s*CALL\b", line, re.I) and needs_check.search(line):
            following = lines[i + 1][1] if i + 1 < len(lines) else ""
            if "ERRORLEVEL" not in following.upper():
                unchecked.append("%s:%d" % (rel, n))
check("every CALL of post_admin.bat or admin_calls.bat is followed by a line that reads ERRORLEVEL",
      not unchecked, "unchecked: %s" % unchecked)

# The examples POST through the helper, which reads the code from the response headers. A raw
# curl with -w "\nHTTP %{http_code}" prints the code and always ends with exit 0
raw = []
for rel in steps_bat + steps_sh:
    base = os.path.basename(rel)
    if base in ("billable_GET_report.sh", "billable_GET_report.bat", "files_GET_download.sh", "files_GET_download.bat"):
        continue
    text = open(os.path.join(REPO, rel), newline="").read().replace("\r\n", "\n")
    code = "\n".join(l for l in text.split("\n") if not re.match(r"\s*(#|REM\b)", l))
    # a call may continue on the next lines (^ or \), so look at the joined text
    joined = re.sub(r"\s*[\\^]\n\s*", " ", code)
    for m in re.finditer(r"^\s*curl\b[^\n]*", joined, re.M):
        call = m.group(0)
        if re.search(r"-X\s+(POST|DELETE)\b", call) or "-w \"\\nHTTP" in call:
            raw.append("%s: %s" % (rel, call.strip()[:80]))
check("no numbered example POSTs or DELETEs with a raw curl that prints the code and exits 0",
      not raw, "raw calls: %s" % raw)


print()
print("test_feature_bat_twins: " + ("PASS" if failed == 0 else "FAIL"))
sys.exit(1 if failed else 0)
