#!/usr/bin/env python3
"""Features/Guidance/testing-your-scripts.md: the worked example in it runs (the stand-in for curl, the script, its test: eight checks pass), and the table of
mutations is true (each of the six changes is caught, or not, by the test and by a test of the exit code only, as the table says). The tools it names exist."""
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
import guide_checks as g  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


text = g.read("testing-your-scripts.md")
heads = re.findall(r"^## (.+)$", text, re.M)
for h in ("Two places to test", "A lab that is not production", "A test with no server: a stand-in for curl", "What a test should check",
          "Would your test notice a broken script?", "Counting what is covered", "Test the days that go wrong", "Checklist"):
    check("section: %s" % h, h in heads, heads)
check("the tools it names exist", all((g.ROOT / p).exists() for p in ("tests/offline/lib/stub_curl", "tools/mutation_probe.py", "tools/script_coverage.py", "tools/measure_coverage.py")))
mp = (g.ROOT / "tools" / "mutation_probe.py").read_text()
ops = re.findall(r"^\| (\w+) \| ", text.split("| Change | What it does |")[1].split("Some survivors")[0], re.M)
check("the operators it lists are the ones the tool has", ops == ["method", "exit", "status", "header", "url", "key", "compare", "output"]
      and all('"%s"' % o in mp for o in ops), ops)
check("the link to the time guide points at a heading that exists", "time-formats.md#how-to-test-your-script-without-waiting-for-the-date" in text
      and "### How to test your script without waiting for the date" in g.read("time-formats.md"))

blocks = [code for lang, code in g.blocks(text) if lang == "bash"]
stub = next(b for b in blocks if b.startswith("#!/bin/bash\n# stubs/curl"))
script = next(b for b in blocks if b.startswith("#!/bin/bash\n# create_folder.sh"))
test = next(b for b in blocks if b.startswith("#!/bin/bash\n# test_create_folder.sh"))
check("the guide says the test has eight checks, and it has", "all eight checks pass" in text and test.count("expect \"") == 8, test.count("expect \""))


def build(script_text=script, test_text=test, stub_text=stub):
    d = tempfile.mkdtemp(prefix="guide_testing_")
    Path(d, "stubs").mkdir()
    for name, body in (("stubs/curl", stub_text), ("create_folder.sh", script_text), ("test_create_folder.sh", test_text)):
        p = Path(d, name)
        p.write_text(body)
        p.chmod(p.stat().st_mode | stat.S_IXUSR)
    return d


def run_test(d):
    r = subprocess.run(["bash", str(Path(d, "test_create_folder.sh"))], capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout


d = build()
rc, out = run_test(d)
check("the worked example: the test passes on the script, all eight checks", rc == 0 and out.count("PASS") == 8 and "FAIL" not in out, out)

# the stand-in refuses a call with no Referer header
r = subprocess.run(["bash", str(Path(d, "stubs/curl")), "-s", "https://x/api", "-H", "accept: a"], capture_output=True, text=True)
check("the small stand-in refuses a call with no Referer", r.returncode == 22 and "no Referer header" in r.stderr, (r.returncode, r.stderr))

# a test that only checks the exit code of a 201
weak = '''#!/bin/bash
cd "$(dirname "$0")" || exit 1
export PATH="${PWD}/stubs:${PATH}" ST_USER=u ST_PASSWORD=p ST_SERVER=st.example.com ST_ENDUSER_PORT=8443
./create_folder.sh reports >/dev/null 2>&1
exit $?
'''
mutants = [
    ("-X POST becomes -X PUT", "-X POST", "-X PUT", False),
    ("the Referer header is removed", ' -H "Referer: x"', "", True),
    ("files/ becomes file/ in the path", "api/v2.0/files/", "api/v2.0/file/", False),
    ('"201" becomes "299"', '"201"', '"299"', True),
    ("exit 1 after the refusal becomes exit 0", "exit 1; }\necho", "exit 0; }\necho", False),
    ("exit 2 in the usage check becomes exit 0", "exit 2; }", "exit 0; }", False),
]
table = text.split("| Change | The test above | A test that only checks the exit code |")[1].split("The weak test misses")[0]
for label, old, new, weak_catches in mutants:
    check("the mutation exists in the script: %s" % label, old in script, old)
    m = build(script_text=script.replace(old, new, 1))
    rc_full, _ = run_test(m)
    wd = build(script_text=script.replace(old, new, 1), test_text=weak)
    rc_weak, _ = run_test(wd)
    check("the full test fails on it: %s" % label, rc_full != 0)
    check("the exit code test %s it, as the table says: %s" % ("catches" if weak_catches else "misses", label), (rc_weak != 0) == weak_catches, (rc_weak, weak_catches))
    shutil.rmtree(m, ignore_errors=True)
    shutil.rmtree(wd, ignore_errors=True)
check("the table says four of the six are missed by the weak test", "The weak test misses four of the six" in text and sum(1 for *_, w in mutants if not w) == 4)
shutil.rmtree(d, ignore_errors=True)

_g = g.read("testing-your-scripts.md")
check("the guide has the lessons of the probes, with the strict stand-in, the whole call, the messages, the refusal paths and the time cap",
      "## What the probes taught us" in _g and "Make the stand-in as strict as the server." in _g and "Check the whole call." in _g
      and "Test every refusal path." in _g and "Cap the time a changed script may run." in _g)
print("test_guidance_testing_your_scripts: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
