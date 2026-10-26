#!/usr/bin/env python3
"""Which example scripts the offline suite really RUNS, not only names (tools/test_map.py only reads the text of checks).

    python3 tools/script_coverage.py            run tests/offline/run_all.sh with a tracer, list the bash and python
                                                scripts that nothing ran
    python3 tools/script_coverage.py --log F    read a log from an earlier run instead
    python3 tools/script_coverage.py --online   the same for tests/online/run_online.sh --write (WRITES TO THE LAB, takes
                                                long; a check is stopped after 10 minutes). The scripts kept out of the
                                                online checks on purpose (tools/test_map.py NO_ONLINE) are not listed.

How: bash reads $BASH_ENV at the start of every non-interactive shell, so a tiny file there records the path of each
script that starts; python scripts are recorded the same way by a sitecustomize on PYTHONPATH. The scripts the tests
run sit in scratch copies, so a record is matched to a tracked script by its folder name and file name. .bat files
cannot run here: their twins are held by the parity checks.
"""
import os, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HELPERS = {"lib.sh", "session.sh", "ensure_session.sh", "settings.sh"}
# imported by the examples, never run on its own: the checks that run the examples run it
LIBRARIES = {"el_client.py"}


def tracked():
    out = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines()
    return [f for f in out if f.endswith((".sh", ".py")) and not f.startswith(("tests/", "tools/", ".claude/", "review/"))
            and Path(f).name not in HELPERS | LIBRARIES and "/lib/" not in f and "example" not in Path(f).name]


def record(log, online=False):
    work = Path(tempfile.mkdtemp(prefix="cov_"))
    # $0 is just "bash" while BASH_ENV is read, so a DEBUG trap notes the script on its first command and goes away
    (work / "env.sh").write_text(
        """[ -n "$COVERAGE_LOG" ] && trap 'case "${BASH_SOURCE[0]}" in /*) _p="${BASH_SOURCE[0]}";; "") _p="";; *) _p="$PWD/${BASH_SOURCE[0]}";; esac; [ -n "$_p" ] && printf "%s\\n" "$_p" >> "$COVERAGE_LOG"; trap - DEBUG' DEBUG\n""")
    # sys.argv is not set yet when sitecustomize runs, so the script is noted when the interpreter exits
    (work / "sitecustomize.py").write_text(
        "import atexit, os, sys\n_l = os.environ.get('COVERAGE_LOG')\n"
        "def _note():\n    if sys.argv and sys.argv[0].endswith('.py'):\n"
        "        open(_l, 'a').write(os.path.abspath(sys.argv[0]) + '\\n')\n"
        "if _l:\n    atexit.register(_note)\n"
        "# the sitecustomize this one hides (the fake requests of the tests has one) still has to run\n"
        "_me = os.path.dirname(os.path.abspath(__file__))\n"
        "for _d in sys.path:\n"
        "    _f = os.path.join(_d or '.', 'sitecustomize.py')\n"
        "    if os.path.exists(_f) and os.path.dirname(os.path.abspath(_f)) != _me:\n"
        "        exec(compile(open(_f).read(), _f, 'exec'))\n"
        "        break\n")
    env = dict(os.environ, BASH_ENV=str(work / "env.sh"), COVERAGE_LOG=str(log),
               PYTHONPATH=str(work) + os.pathsep + os.environ.get("PYTHONPATH", ""), COVERAGE_PYTHONPATH=str(work))
    if online:
        env["ST_CHECK_TIMEOUT"] = "600"
        cmd = [str(ROOT / "tests/online/run_online.sh"), "--write"]
    else:
        cmd = [str(ROOT / "tests/offline/run_all.sh")]
    subprocess.run(cmd, cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    """Prints the gaps; returns 1 when there is one (a script nothing ran, or, offline, one that never made a call)."""
    if "--log" in sys.argv:
        log = Path(sys.argv[sys.argv.index("--log") + 1])
    else:
        log = Path(tempfile.mkdtemp(prefix="covlog_")) / "log.txt"
        log.write_text("")
        record(log, "--online" in sys.argv)
    lines = [p for p in log.read_text().split("\n") if p]
    # a check that must dodge a name on the lab runs a copy called .zztest_<name> next to the script
    paths = [p.replace("/.zztest_", "/") for p in lines if not p.startswith("CALL ")]
    # the scripts that made a call to the server (the stub curl), from the parent command line of each call
    called = set()
    for p in lines:
        if p.startswith("CALL "):
            for tok in p[5:].split():
                if tok.endswith((".sh", ".py")):
                    called.add(Path(tok).name)
    ran = {(Path(p).parent.name, Path(p).name) for p in paths}
    ran_names = {Path(p).name for p in paths}
    files = tracked()
    if "--online" in sys.argv:
        sys.path.insert(0, str(ROOT / "tools"))
        import test_map
        files = [f for f in files if not any(k in f for k in test_map.NO_ONLINE)]
    count = {}
    for f in files:
        count[Path(f).name] = count.get(Path(f).name, 0) + 1
    # a test may copy scripts into a flat scratch folder: a file name that only one script has is enough, one that
    # several have (00.run_all.sh) needs its folder as well
    missing = [f for f in files if not ((Path(f).parent.name, Path(f).name) in ran
               or (count[Path(f).name] == 1 and Path(f).name in ran_names))]
    for f in missing:
        print(f)
    silent = []
    if "--online" not in sys.argv:   # the stub that notes calls is the offline one
        # a script that talks to the server, that ran, and never got as far as a call: only its usage was tried
        silent = [f for f in files if f not in missing and Path(f).name not in called and Path(f).suffix == ".sh"
                  and "curl" in (ROOT / f).read_text(errors="replace") and "run_all" not in f and not Path(f).name.startswith("99.")]
        print(f"\nran, but never reached a call to the server ({len(silent)}): their usage or an early exit is all that is tested")
        for f in silent:
            print("  " + f)
    problems = len(missing) + (len(silent) if "--online" not in sys.argv else 0)
    kind = "online" if "--online" in sys.argv else "offline"
    print(f"\n{len(missing)} of {len(files)} scripts were not run by any {kind} check (log: {log})")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
