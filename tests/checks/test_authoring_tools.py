#!/usr/bin/env python3
"""
Check the tools in .claude/skills/st-api-cover-resource/scripts that new Admin
examples are written with: the spec reader, the bash and bat writers, and the
docs sync. A wrong header from them would spread to every file written next.

Runs offline, on a synthetic slice of the reference and a temporary folder.
Exit code 0 means clean.
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(REPO, ".claude", "skills", "st-api-cover-resource", "scripts")
sys.path.insert(0, TOOLS)
import endpoint  # noqa: E402
import authoring  # noqa: E402

MINI = os.path.join(REPO, "tests", "fixtures", "admin20-spec-mini")
failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1


print("=== endpoint.py ===")
ops = endpoint.operations(MINI)
check("every operation, with its tag and summary, the 6-space block included",
      [(t, p, m) for t, p, m, _ in ops] == [("gadgets", "/gadgets", "GET"), ("widgets", "/widgets", "GET"),
                                           ("widgets", "/widgets", "POST"), ("widgets", "/widgets/{name}", "HEAD"),
                                           ("widgets", "/widgets/{name}", "DELETE")], ops)
check("a parameter's '- name:' is not taken for a tag", all(t in ("gadgets", "widgets") for t, _, _, _ in ops))
check("tags in the reference's own order, not the order of the paths", endpoint.tag_order(MINI) == ["widgets", "gadgets"],
      endpoint.tag_order(MINI))
check("show() prints a path and those under it", "/widgets/{name}:" in endpoint.show(["/widgets"], MINI)
      and "/gadgets:" not in endpoint.show(["/widgets"], MINI))

print("=== authoring.py ===")
os.environ["ST_AUTHOR"], os.environ["ST_LOCATION"] = "Test Author", "Testville"
with tempfile.TemporaryDirectory() as work:
    sh_root, bat_root = os.path.join(work, "bash"), os.path.join(work, "bat")
    sh = authoring.write_sh("99.Widgets", "01.widgets_GET.sh", ["This script lists widgets."],
                            ["./01.widgets_GET.sh [NAME]"],
                            ["- NAME defaults to example_widget, so export it first:",
                             "    export WIDGET_KEY='a key'", "- Requires `jq`, which looks the id up."],
                            'printf "%s\\n" "${MAIN_URL}"\n', main_url="widgets", root=sh_root, risk="read")
    text = open(sh).read()
    check("bash: the house header, with the name, author and location",
          text.startswith("#!/bin/bash\n# ====") and "# Script Name: 01.widgets_GET.sh\n# Author: Test Author\n" in text
          and "# Location: Testville\n" in text, text[:300])
    check("bash: set_variables sourced from the script's folder, the Referer and MAIN_URL set",
          'source "${SCRIPT_DIR}/../set_variables.sh"' in text and 'REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"' in text
          and 'MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/widgets"' in text)
    check("bash: the Risk line, between Usage and Notes", "# ./01.widgets_GET.sh [NAME]\n#\n# Risk: read\n#\n# Notes:" in text, text[:700])
    try:
        authoring.write_sh("99.Widgets", "02.widgets_POST.sh", ["x"], ["x"], [], "", root=sh_root)
        refused = False
    except ValueError:
        refused = True
    check("bash: a missing or unknown risk is refused", refused)
    check("bat: the Risk line goes to the twin", "REM Risk: read\n" in open(authoring.write_bat("99.Widgets", "01.widgets_GET.bat", "", root=bat_root, sh_root=sh_root)).read())
    check("bash: executable, and bash -n passes", os.access(sh, os.X_OK)
          and subprocess.run(["bash", "-n", sh]).returncode == 0)
    bat = authoring.write_bat("99.Widgets", "01.widgets_GET.bat", "echo done\n", main_url="widgets",
                              root=bat_root, sh_root=sh_root)
    text = open(bat).read()
    check("bat: the same header as REM lines, named for the bat", text.startswith("@echo off\nREM ====")
          and "REM Script Name: 01.widgets_GET.bat\n" in text and "REM This script lists widgets.\n" in text, text[:300])
    check("bat: usage without ./, export turned into SET, jq into PowerShell",
          "REM 01.widgets_GET.bat [NAME]" in text and "REM     SET WIDGET_KEY=a key" in text
          and "so set it first" in text and "REM - PowerShell is used to look the id up, in place of jq." in text, text)
    check("bat: set_variables called, MAIN_URL set, the body after",
          "CALL ..\\set_variables.bat" in text and "SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/widgets" in text
          and text.endswith("echo done\n"))

# The committed twins written with these tools must still match what they write now
skip = re.compile(r"^REM (Author|Created|Location):")
drift = []
for folder in ("11.Certificates", "13.Configurations", "20.AdministrativeRoles", "21.Administrators"):
    for path in sorted(glob.glob(os.path.join(authoring.BAT, folder, "*.bat"))):
        name = os.path.basename(path)
        if name[:2] in ("01", "02") and folder == "13.Configurations":
            continue  # written by hand, before the tools
        made = [l for l in authoring.bat_header(folder, name).split("\n") if not skip.match(l)]
        have = [l for l in open(path).read().split("\n") if not skip.match(l)]
        # Compare the REM text with line wrapping ignored: a long line may be wrapped by hand
        doc = lambda lines: " ".join(" ".join(l[3:].split()) for l in lines[:lines.index("SETLOCAL")] if l.startswith("REM"))
        if doc(have) != doc(made):
            drift.append(folder + "/" + name)
check("the committed bat headers match what bat_header() writes from their bash twins", not drift, drift[:5])

print("=== scratch_path ===")
import _repo  # noqa: E402
scratch = _repo.scratch_path("example_scratch.json")
check("scratch_path gives a file in tmp/ at the project root, and creates the folder",
      scratch == os.path.join(REPO, "tmp", "example_scratch.json") and os.path.isdir(os.path.join(REPO, "tmp")), scratch)
ignored = subprocess.run(["git", "-C", REPO, "check-ignore", "-q", scratch])
check("git ignores it, so scratch state is never committed", ignored.returncode == 0)

print("=== sync_docs.py ===")
result = subprocess.run([sys.executable, os.path.join(TOOLS, "sync_docs.py"), "--check"], capture_output=True, text=True)
check("--check finds the README, the docs check and the pack in line with the folders", result.returncode == 0,
      result.stdout + result.stderr)

print()
print("test_authoring_tools: %s" % ("PASS" if not failed else "FAIL"))
sys.exit(1 if failed else 0)
