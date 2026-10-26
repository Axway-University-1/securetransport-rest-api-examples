#!/usr/bin/env python3
"""The known failures of the online checks (tests/common/known_failures.py, tests/online/known_failures.tsv):
the judging, the report of one that is fixed, the list itself, and run_online.sh end to end on stand-in checks."""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tests" / "common"))
import known_failures as kf  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


tmp = Path(tempfile.mkdtemp(prefix="kf_"))
rows = [("46", "THE POLICY ENFORCES", "RD-19"), ("59", "did not finish within", "callback host")]
state = str(tmp / "state")
A = "  PASS  something\n  FAIL  SFTP: THE POLICY ENFORCES: refused  got: ok after 10 tries\n"
check("a failure that is in the list is known", kf.judge(rows, "46.x.py", A, state) == "known")
check("one more FAIL line that is not in the list makes it unknown",
      kf.judge(rows, "46.x.py", A + "  FAIL  a new problem\n", state) == "unknown")
check("a check with no FAIL line is clean", kf.judge(rows, "46.x.py", "  PASS  a\n", state) == "clean")
check("the text of one check does not excuse another", kf.judge(rows, "47.y.py", A, state) == "unknown")
check("a number is not a prefix of a longer number (46 is not 460)", kf.judge(rows, "460.y.py", A, state) == "unknown")
kf.judge(rows, "46.x.py", A, state)
check("a list line that fired is not reported as fixed", kf.report(rows[:1], state) == 0)
state2 = str(tmp / "state2")
kf.judge(rows, "46.x.py", "  PASS  a\n", state2)
check("... the fixed one is reported (46 ran and was clean)", kf.report(rows[:1], state2) == 1)
check("a line whose check did not run is not reported", kf.report(rows[1:], state2) == 0)
try:
    p = tmp / "bad.tsv"
    p.write_text("46\tonly two columns\n")
    kf.read_list(str(p))
    check("a list line with no reason is refused", False)
except SystemExit:
    check("a list line with no reason is refused", True)

# the list itself: every line names a check that exists, and a reason
listed = kf.read_list(str(ROOT / "tests" / "online" / "known_failures.tsv"))
names = [p.name for p in (ROOT / "tests" / "online" / "checks").glob("*.py")]
for key, text, why in listed:
    check("known_failures.tsv: '%s' names a check that exists" % key, any(kf.applies(key, n) for n in names))

# run_online.sh end to end, with stand-in checks that fail the way a listed one does, and one that does not
work = tmp / "tests"
(work / "online" / "checks").mkdir(parents=True)
shutil.copy(ROOT / "tests" / "online" / "run_online.sh", work / "online" / "run_online.sh")
shutil.copytree(ROOT / "tests" / "common", work / "common", ignore=shutil.ignore_patterns("__pycache__"))
(work / "online" / "known_failures.tsv").write_text("9001\tKNOWN TEXT\tbecause\n9003\tNEVER PRINTED\tfixed already\n")
conf = tmp / "integration.conf"
conf.write_text('st_server="127.0.0.1"\nst_port="1"\nst_user="u"\nst_password="p"\nst_confirm_lab="yes"\n')
(work / "online" / "checks" / "9001.known.py").write_text("print('  FAIL  KNOWN TEXT here')\nprint('  3 passed, 1 failed')\nraise SystemExit(1)\n")
(work / "online" / "checks" / "9003.fixed.py").write_text("print('  PASS  it works now')\nprint('  1 passed, 0 failed')\n")
(work / "online" / "checks" / "9002.fine.py").write_text("print('  PASS  fine')\nprint('  1 passed, 0 failed')\n")


def run_online(extra):
    env = dict(os.environ, ST_INTEGRATION_CONF=str(conf))
    r = subprocess.run(["bash", str(work / "online" / "run_online.sh")] + extra, capture_output=True, text=True, env=env, timeout=120)
    return r.returncode, r.stdout + r.stderr


rc, out = run_online(["900"])
check("a listed line whose check ran and no longer fails turns the run red, and is named", rc == 1 and "A KNOWN FAILURE IS FIXED" in out and "9003" in out and "ONLINE PASSED" not in out,
      (rc, out[-400:]))
(work / "online" / "known_failures.tsv").write_text("9001\tKNOWN TEXT\tbecause\n")
rc, out = run_online(["900"])
check("with no stale line in the list it ends green, and names the known failure", rc == 0 and "ONLINE PASSED" in out and "1 known failure(s)" in out
      and "9001.known.py" in out, (rc, out[-400:]))
(work / "online" / "checks" / "9003.fixed.py").write_text("print('  FAIL  something new')\nprint('  0 passed, 1 failed')\nraise SystemExit(1)\n")
rc, out = run_online(["900"])
check("a failure that is not in the list turns the run red", rc == 1 and "1 ONLINE CHECK(S) FAILED" in out and "9003.fixed.py" in out, (rc, out[-400:]))
shutil.rmtree(tmp, ignore_errors=True)
print("test_known_failures: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
