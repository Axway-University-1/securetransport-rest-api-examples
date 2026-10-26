#!/usr/bin/env python3
"""tools/measure_coverage.py: the report is built from the stored measures, says when each was taken, merges mutation results of
different scripts, and keeps a history that --history shows. (The measures themselves are tested where they live:
test_script_coverage.py, check_script_conventions.py; the mutation probe is tested in test_mutation_probe.py.)"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
tmp = tempfile.mkdtemp(prefix="mc_")
os.environ["ST_COVERAGE_DIR"] = tmp
sys.path.insert(0, str(ROOT / "tools"))
import measure_coverage as mc  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


check("the output folder can be moved (ST_COVERAGE_DIR)", str(mc.OUT) == tmp)
check("pct: a share, and n/a for nothing", mc.pct(1, 4) == "25%" and mc.pct(0, 0) == "n/a")

new = {"made": "2026-10-26", "results": [{"script": "a.sh", "tests": ["t"], "mutants": [
    {"verdict": "killed", "line": 1, "operator": "exit", "before": "x", "after": "y"},
    {"verdict": "survived", "line": 2, "operator": "header", "before": "-H a", "after": ""},
    {"verdict": "invalid", "line": 3, "operator": "url", "before": "u", "after": "v"}]}]}
state = {"mutation": mc.merge_mutation({}, new)}
check("a mutant that does not parse is not counted", state["mutation"]["valid"] == 2 and state["mutation"]["killed"] == 1)
more = {"made": "2026-10-27", "results": [{"script": "b.sh", "tests": ["t"], "mutants": [
    {"verdict": "killed", "line": 1, "operator": "exit", "before": "x", "after": "y"}]}]}
state["mutation"] = mc.merge_mutation(state, more)
check("the results of another script are added, not replacing the first", state["mutation"]["scripts"] == 2 and state["mutation"]["valid"] == 3
      and state["mutation"]["killed"] == 2)
again = {"made": "2026-10-28", "results": [{"script": "a.sh", "tests": ["t"], "mutants": [
    {"verdict": "killed", "line": 1, "operator": "exit", "before": "x", "after": "y"}]}]}
state["mutation"] = mc.merge_mutation(state, again)
check("probing a script again replaces its earlier result", state["mutation"]["scripts"] == 2 and state["mutation"]["valid"] == 2)

state["offline"] = {"date": "2026-10-20", "data": {"total": 10, "run": 9, "missing": ["Admin/x.sh"], "with_calls": 8, "called": 6, "silent": ["Admin/y.sh", "Admin/z.sh"]}}
state["api"] = {"date": "2026-10-26", "data": {"admin": {"total": 4, "covered": 3, "missing": ["GET /x (t)"]}, "enduser": {"error": "no reference"}}}
state["rules"] = {"date": "2026-10-26", "data": {"scripts": 5, "problems": []}}
text, rows = mc.build(state)
check("the report says what was not run", "not run: Admin/x.sh" in text and "never calls the server in a test: Admin/y.sh" in text)
check("the report gives a share for each measure", "Run by a check: 9 of 10 (90%)" in text and "6 make a call in a test (75%)" in text
      and "admin: 3 of 4 (75%)" in text)
check("it shows the date a measure was taken", "(measured 2026-10-20)" in text)
check("a measure that was not taken says so", "Not measured: run with --offline" not in text and "Not measured: run with --online" in text)
state["mutation"] = mc.merge_mutation({"mutation": mc.merge_mutation({}, new)}, more)       # a.sh 1 of 2, b.sh 1 of 1
text2, _ = mc.build(state)
check("the weakest script comes first in the assertion depth", text2.index("a.sh") < text2.index("b.sh"))
check("a survivor is listed under its script", "survived: line 2, header" in text2)
check("a row for the history has one value per column", len(rows) == len(mc.HEADER) - 2, rows)
check("the missing reference is a note, not a crash", "enduser: no reference" in text)

# history
(Path(tmp) / "history.tsv").write_text("\t".join(mc.HEADER) + "\n2026-10-20\tabc1234\t90%\t100%\t95%\t90%\t50%\t80%\t3\tclean\n")
r = subprocess.run([sys.executable, str(ROOT / "tools" / "measure_coverage.py"), "--history"], capture_output=True, text=True, env=dict(os.environ, ST_COVERAGE_DIR=tmp))
check("--history shows the rows of earlier reports", r.returncode == 0 and "abc1234" in r.stdout and "mutation_caught" in r.stdout, r.stdout + r.stderr)
print("test_measure_coverage: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
