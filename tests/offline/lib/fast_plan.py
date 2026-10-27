#!/usr/bin/env python3
"""Which offline checks the quick run (tests/offline/run_fast.sh) runs.

Everything except the slow ones (each takes more than 10 seconds: together about 6 of the 8 minutes of the whole suite), plus the slow ones that matter
for what changed since the last commit: the check that covers a changed script (the one that names it), a changed check, and the test of a changed tool.

    python3 fast_plan.py              the paths of the checks to run, relative to tests/offline, one per line
    python3 fast_plan.py --why        the same with the reason for the slow ones that were added
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CHECKS = ROOT / "tests" / "offline" / "checks"

# Slow: more than about 10 seconds each when the suite last ran (see the table in tests/README.md, "The quick run")
SLOW = {
    "test_feature_billable_transfers.sh", "test_python_scripts_run.py", "test_feature_trigger_route_pull.sh", "test_bash_admin_api.sh",
    "test_python_safety.py", "test_python_graceful.py", "test_integration_helpers.py", "test_bash_admin_sweep_a.sh", "test_bash_admin_sweep_c.sh",
}


def changed_files():
    """Files changed since the last commit, and new ones."""
    out = subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=ROOT, text=True).splitlines()
    out += subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard"], cwd=ROOT, text=True).splitlines()
    return sorted(set(out))


def all_checks():
    return sorted(p.name for p in CHECKS.iterdir() if p.is_file() and p.name.startswith(("check_", "test_")) and p.suffix in {".py", ".sh"})


def plan(changed, checks=None, slow=SLOW, reader=lambda p: p.read_text(errors="replace")):
    """([checks to run], {slow check: why}) for the changed files."""
    checks = checks if checks is not None else all_checks()
    texts = {}

    def text(name):
        if name not in texts:
            texts[name] = reader(CHECKS / name)
        return texts[name]

    why = {}
    for f in changed:
        name = Path(f).name
        if f.startswith("tests/offline/checks/") and name in checks and name in slow:
            why[name] = "it changed"
        elif f.startswith("tests/offline/lib/") or f.startswith("tools/"):
            stem = Path(f).stem
            for c in checks:
                if c in slow and (stem in c or stem in text(c)):
                    why.setdefault(c, "it uses %s, which changed" % name)
        elif name.endswith((".sh", ".py", ".bat")) and not f.startswith("tests/"):
            for c in checks:
                if c in slow and name in text(c):
                    why.setdefault(c, "it covers %s, which changed" % name)
    run = [c for c in checks if c not in slow or c in why]
    return run, why


if __name__ == "__main__":
    run, why = plan(changed_files())
    for c in run:
        print("checks/" + c)
    if "--why" in sys.argv:
        for c, w in why.items():
            print("# slow check added: %s: %s" % (c, w), file=sys.stderr)
