#!/usr/bin/env python3
"""tools/script_coverage.py reads a log of what the offline suite ran: check that it matches a record to a script, by
folder and file name, or by file name alone when no other script has it, and tells a script that was run but never made
a call to the server. (Whether the suite really runs everything is `python3 tools/script_coverage.py`, which runs it.)"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / "tools" / "script_coverage.py"
failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % detail))
    if not ok:
        failed.append(label)


def run_tool(lines):
    with tempfile.TemporaryDirectory() as d:
        log = Path(d) / "log.txt"
        log.write_text("\n".join(lines) + "\n")
        return subprocess.run([sys.executable, str(TOOL), "--log", str(log)], capture_output=True, text=True)


def report(lines):
    return run_tool(lines).stdout


unique = "Admin/API 2.0/bash/05.Accounts/05.accounts_name_PUT.sh"          # a file name only one script has
shared = "EndUser/UseCases/06-sharing-a-folder/00.run_all.sh"                # 00.run_all.sh: many scripts have it
out = report(["/scratch/flat/05.accounts_name_PUT.sh", "/scratch/06-sharing-a-folder/00.run_all.sh"])
check("a script run from a scratch folder is found by its file name when it is the only one with it", unique not in out.split("\n\n")[0])
check("00.run_all.sh is found by its folder", shared not in out.split("\n\n")[0])
check("another 00.run_all.sh, whose folder was not run, is listed as not run", "EndUser/UseCases/05-checking-transfers/00.run_all.sh" in out.split("\n\n")[0])
check("a script nothing ran is listed", "Admin/API 2.0/bash/05.Accounts/02.accounts_POST.sh" in out.split("\n\n")[0])
out = report(["/s/05.accounts_name_PUT.sh"])
check("a script that ran but made no call is reported as such", "05.accounts_name_PUT.sh" in out.split("never reached a call")[-1])
out = report(["/s/05.accounts_name_PUT.sh", "CALL bash ./05.accounts_name_PUT.sh a b"])
check("and not once a call came from it", "05.accounts_name_PUT.sh" not in out.split("never reached a call")[-1])
check("a log with gaps is exit 1", run_tool(["/s/05.accounts_name_PUT.sh"]).returncode == 1)
# a log in which every tracked script ran, and every one that talks to the server made a call: exit 0
import importlib.util
spec = importlib.util.spec_from_file_location("script_coverage", TOOL)
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)
everything = []
for f in sc.tracked():
    everything.append("/scratch/%s/%s" % (Path(f).parent.name, Path(f).name))
    everything.append("CALL bash ./%s" % Path(f).name)
r = run_tool(everything)
check("a log in which everything ran and called is exit 0", r.returncode == 0, r.stdout[-300:])
check("el_client.py, a library, is not asked for", "el_client.py" not in report([]))
print("test_script_coverage: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
