#!/usr/bin/env python3
"""
Two test runs at the same time do not delete each other's files.

The bash checks keep their scratch files in a folder named after the check (tests/output/bash_payloads and so on) and
start by deleting it. Two `./tests/run_all.sh` at once, or a full run next to a single check, therefore deleted each
other's folder in the middle of a run and failed in ways that looked like a bug in the examples. Now the folder is
under ST_TEST_OUTPUT, and run_all.sh makes a new one for each run (tests/output/run.XXXXXX), removes it when every
check passed and keeps it, saying where, when one failed.

This checks:
  - that no check still writes to tests/output directly (a new one that forgets ST_TEST_OUTPUT is found here);
  - that the same check, started twice at once with a root each, passes both times and writes only in its own root;
  - what run_all.sh does with its folder: a new one for each run, two runs at once get two, the folder is gone after a
    run that passed and still there, and named in the last lines, after one that did not.

Runs offline. Exit code 0 means clean.
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
TESTS = os.path.join(REPO, "tests")

failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1


print("=== every check keeps its files under ST_TEST_OUTPUT ===")
offenders = []
for path in sorted(glob.glob(os.path.join(TESTS, "checks", "*.sh"))):
    text = open(path).read()
    uses_output = re.findall(r"^[A-Z_]+=.*\$\{?TESTS_DIR\}?/output", text, re.M)
    plain = [line for line in uses_output if "ST_TEST_OUTPUT" not in line]
    if plain:
        offenders.append(os.path.basename(path))
check("no bash check names tests/output without ST_TEST_OUTPUT", not offenders, offenders)
check("and the ones that use it are there to be read", len([p for p in glob.glob(os.path.join(TESTS, "checks", "*.sh"))
                                                          if "ST_TEST_OUTPUT" in open(p).read()]) >= 10)

print("=== the same check twice at once, each with a root of its own ===")
CHECK = os.path.join(TESTS, "checks", "test_bash_pesit_ack.sh")
roots = [tempfile.mkdtemp(prefix="output_root_") for _ in range(2)]
try:
    procs = [subprocess.Popen(["bash", CHECK], env=dict(os.environ, ST_TEST_OUTPUT=root), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
             for root in roots]
    outs = [p.communicate(timeout=300)[0] for p in procs]
    check("both pass: neither deleted the other's folder under it", [p.returncode for p in procs] == [0, 0],
          [(p.returncode, o[-300:]) for p, o in zip(procs, outs)])
    check("each wrote in its own root, and only there", all(os.listdir(root) == ["bash_pesit_ack"] for root in roots), [os.listdir(r) for r in roots])
finally:
    for root in roots:
        shutil.rmtree(root, ignore_errors=True)

print("=== what run_all.sh does with its folder ===")
work = tempfile.mkdtemp(prefix="run_all_test_")
try:
    tests = os.path.join(work, "tests")
    os.makedirs(os.path.join(tests, "checks"))
    shutil.copy(os.path.join(TESTS, "run_all.sh"), tests)

    def write(name, text):
        with open(os.path.join(tests, "checks", name), "w") as f:
            f.write(text)
    # records the folder it was given, uses it, and waits a moment so that two runs overlap
    write("test_ok.sh", '#!/bin/bash\necho "ROOT ${ST_TEST_OUTPUT}"\nmkdir -p "${ST_TEST_OUTPUT}/ok" && echo x > "${ST_TEST_OUTPUT}/ok/file"\nsleep "${HOLD:-0}"\n')
    write("test_bad.sh", '#!/bin/bash\necho "ROOT ${ST_TEST_OUTPUT}"\necho x > "${ST_TEST_OUTPUT}/bad_file"\nexit 1\n')

    def run_all(*args, **env):
        return subprocess.Popen(["bash", os.path.join(tests, "run_all.sh")] + list(args), env=dict(os.environ, **env),
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    p = run_all("ok")
    out = p.communicate(timeout=60)[0]
    root = re.search(r"^ROOT (.*)$", out, re.M).group(1)
    check("a run gives the checks a folder of its own under tests/output: %s" % os.path.relpath(root, work),
          os.path.dirname(root) == os.path.join(tests, "output") and os.path.basename(root).startswith("run."), root)
    check("a run that passed removes it again, and exits 0", p.returncode == 0 and not os.path.exists(root) and "ALL CHECKS PASSED" in out, (p.returncode, out[-200:]))

    p = run_all("bad")
    out = p.communicate(timeout=60)[0]
    root = re.search(r"^ROOT (.*)$", out, re.M).group(1)
    check("a run with a failure keeps the folder, so that it can be read, and exits 1", p.returncode == 1 and os.path.exists(os.path.join(root, "bad_file")),
          (p.returncode, os.path.exists(root)))
    check("and says where it is, in the last lines", ("kept in " + root) in out.split("CHECK(S) FAILED")[-1], out[-300:])

    first, second = run_all("ok", HOLD="3"), run_all("ok", HOLD="3")
    time.sleep(1.5)     # both are inside the check now
    outs = [first.communicate(timeout=60)[0], second.communicate(timeout=60)[0]]
    roots = [re.search(r"^ROOT (.*)$", o, re.M).group(1) for o in outs]
    check("two runs at once get two different folders", roots[0] != roots[1], roots)
    check("and both pass: neither removed what the other was using", first.returncode == 0 and second.returncode == 0, (first.returncode, second.returncode))
    check("and both removed their own", not any(os.path.exists(r) for r in roots), roots)

    leftovers = glob.glob(os.path.join(tests, "output", "run.*"))
    check("only the run that failed left a folder", len(leftovers) == 1, leftovers)
finally:
    shutil.rmtree(work, ignore_errors=True)

print()
if failed:
    print("test_output_folders: FAIL (%d)" % failed)
    sys.exit(1)
print("test_output_folders: PASS")
