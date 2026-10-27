#!/usr/bin/env python3
"""The quick run (tests/offline/run_fast.sh, lib/fast_plan.py): which checks it runs, and which slow ones it adds for what changed."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tests" / "offline" / "lib"))
import fast_plan as fp  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


checks = ["check_docs.py", "test_quick.py", "test_slow_a.sh", "test_slow_b.py", "test_slow_c.sh"]
slow = {"test_slow_a.sh", "test_slow_b.py", "test_slow_c.sh"}
texts = {"test_slow_a.sh": "runs 13.servers_operations_POST.sh", "test_slow_b.py": "uses stub_curl and fake_requests", "test_slow_c.sh": "nothing special",
         "check_docs.py": "", "test_quick.py": ""}
reader = lambda p: texts[p.name]


def plan(changed):
    return fp.plan(changed, checks, slow, reader)


run, why = plan([])
check("with nothing changed it runs the quick checks and none of the slow ones", run == ["check_docs.py", "test_quick.py"] and not why, (run, why))
run, why = plan(["Admin/API 2.0/bash/03.Connect/13.servers_operations_POST.sh"])
check("a changed script adds the slow check that names it", "test_slow_a.sh" in run and "test_slow_b.py" not in run and "13.servers_operations_POST.sh" in why["test_slow_a.sh"], (run, why))
run, why = plan(["tests/offline/checks/test_slow_c.sh"])
check("a changed slow check is run", "test_slow_c.sh" in run and why["test_slow_c.sh"] == "it changed", (run, why))
run, why = plan(["tests/offline/lib/stub_curl"])
check("a changed stub adds the slow checks that use it", "test_slow_b.py" in run and "test_slow_a.sh" not in run, (run, why))
run, why = plan(["README.md", "Features/Guidance/time-formats.md"])
check("a change that no slow check covers adds nothing", not why, why)

# the real list: every check is either in the quick run or in the slow set, and every name of the slow set exists
allc = fp.all_checks()
check("every name in the slow set is a real check", all(s in allc for s in fp.SLOW), [s for s in fp.SLOW if s not in allc])
run, _ = fp.plan([], allc)
check("the quick run is the rest of the checks", sorted(run + sorted(fp.SLOW)) == sorted(allc))
check("the house rules, the docs check and the guide tests are in the quick run", all(n in run for n in ("check_script_conventions.py", "check_docs_match_repo.py", "test_feature_guidance.py")))
out = subprocess.run(["bash", str(ROOT / "tests" / "offline" / "run_fast.sh"), "--list"], capture_output=True, text=True)
check("run_fast.sh --list prints checks and runs nothing", out.returncode == 0 and "checks/check_docs_match_repo.py" in out.stdout, out.stderr[-200:])
print("test_fast_plan: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
