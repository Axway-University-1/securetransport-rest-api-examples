#!/usr/bin/env python3
"""tools/mutation_probe.py: the changes it makes to a script, where it makes them, and how it reports. (That a check really fails on
a broken script is what the tool is for; it is run by hand, see its docstring.)"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
import mutation_probe as mp  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


SCRIPT = '''#!/bin/bash
# ==============================================================================
# Usage: ./x.sh NAME   (a comment: never changed: curl -X POST exit 1)
# ==============================================================================
source "${HOME}/settings.sh" || { echo "no settings"; exit 1; }
NAME="$1"
if [ "$#" -gt 1 ]; then printf "Usage: x.sh NAME\\n"; exit 2; fi
RESPONSE=$(curl -s -k -X POST "${ST_URL}/accounts" -H "Content-Type: application/json" -H "${REFERER_HEADER}" \\
  -d '{"name": "x"}' -w "\\n%{http_code}")
if [ "${HTTP_CODE}" != "201" ]; then printf "refused\\n"; exit 1; fi
printf "done\\n"
'''
ms = mp.mutants(SCRIPT, 5)
by = {}
for m in ms:
    by.setdefault(m["operator"], []).append(m)
check("the comment header is not touched", all(m["line"] > 4 for m in ms))
check("a method is swapped (POST becomes PUT) on the call, not in the comment", len(by.get("method", [])) == 1
      and by["method"][0]["after"].count("-X PUT") == 1 and by["method"][0]["line"] == 8, by.get("method"))
check("a refusal that stops the script no longer stops it (exit 1 and exit 2 become exit 0)",
      len(by.get("exit", [])) >= 3 and all(m["text"].count("exit 0") == SCRIPT.count("exit 0") + 1 for m in by["exit"]))
check("the status code waited for changes", any('"299"' in m["text"] for m in by.get("status", [])))
check("a header is dropped", any("Content-Type" not in m["text"].split("curl")[1].split("\n")[0] for m in by.get("header", [])))
check("the URL path gets a wrong segment", any("/xaccounts" in m["text"] for m in by.get("url", [])))
check("a name in the body is sent under another name", any('"nameX"' in m["text"] for m in by.get("key", [])))
check("a comparison is turned round", any('"$#" -le 1' in m["text"] for m in by.get("compare", [])))
check("an output line is removed, and counted apart", any(m["after"] == "(line removed)" for m in by.get("output", [])))
check("each mutant is one change: the text differs from the script in one line only",
      all(sum(1 for a, b in zip(SCRIPT.split("\n"), m["text"].split("\n")) if a != b) == 1 for m in ms))
few = mp.mutants(SCRIPT, 1)
check("--per-operator limits the number made at each kind of place", all(sum(1 for m in few if m["operator"] == op) <= 1 for op in {m["operator"] for m in few}))
check("the sites are spread: 2 of 5 sites are not the first two", mp.spread(list(range(10)), 2) == [0, 5])

check("a test names the script it covers (test_map-like search)", "test_bash_admin_sweep_a.sh" in mp.covering_tests("Admin/API 2.0/bash/03.Connect/13.servers_operations_POST.sh"))
check("the house rules cover every script, and run last", mp.covering_tests("Admin/API 2.0/bash/03.Connect/13.servers_operations_POST.sh")[-1] == "check_script_conventions.py")
check("a script no test names is covered by the house rules only", mp.covering_tests("Admin/nothing/no_such" + "_script_zz.sh") == ["check_script_conventions.py"])

report = mp.render([{"script": "x.sh", "tests": ["t"], "mutants": [
    {"operator": "exit", "line": 5, "before": "a", "after": "b", "verdict": "killed"},
    {"operator": "header", "line": 8, "before": "c", "after": "d", "verdict": "survived"},
    {"operator": "url", "line": 9, "before": "e", "after": "f", "verdict": "invalid"}]}])
check("the report counts caught and not counted separately", "1 did not parse" in report and "Caught: 1 of 2 (50%)" in report, report)
check("it lists the survivor with its line", "line 8, header" in report)

# ---- python examples
PY = '''#!/usr/bin/env python3
"""A module docstring that says requests.post(x) and sys.exit(1) and 'Referer': a and "status_code == 200" and print("hi").
It runs over several lines: none of it is ever changed."""
import sys
import requests

# a comment: requests.get(url) sys.exit(2)
def run(session, stUrl, token):
    headers = {'Referer': 'x',
               'csrfToken': token,
               'Content-Type': 'application/json'}
    body = {"loginName": "x", "ttl": 3}
    response = session.post(stUrl + 'deniedUsers', headers=headers, json=body)
    if response.status_code != 201:
        print("Could not block the user")
        sys.exit(1)
    print("Blocked")
    return response.status_code == 201 and body
'''
pm = mp.mutants(PY, 5, python=True)
pby = {}
for m in pm:
    pby.setdefault(m["operator"], []).append(m)
check("python: no line of the docstring or of a comment is touched", all(m["line"] > 5 and m["line"] != 8 for m in pm), [m["line"] for m in pm][:6])
check("python: a session.post is turned into session.put", any("session.put(" in m["after"] for m in pby.get("method", [])))
check("python: sys.exit(1) no longer exits with an error", any(m["after"] == "sys.exit(0)" for m in pby.get("exit", [])))
check("python: the status compared changes to 299", any("299" in m["after"] for m in pby.get("status", [])))
check("python: a Referer, a csrfToken and a Content-Type entry are each dropped",
      {m["before"].split("'")[1] for m in pby.get("header", []) if m["before"].startswith("'") or "'Referer'" in m["before"]} >= {"csrfToken", "Content-Type"}
      and any("Referer" in m["before"] and "Referer" not in m["after"] for m in pby.get("header", [])), pby.get("header"))
check("python: the path of the API gets a wrong first letter", any("'xdeniedUsers'" in m["after"] for m in pby.get("url", [])), pby.get("url"))
check("python: a key of a body is renamed, a header key is not", any('"loginNameX"' in m["after"] for m in pby.get("key", []))
      and not any("RefererX" in m["after"] for m in pby.get("key", [])), pby.get("key"))
check("python: a comparison is turned round", any("== 201" in m["before"] and "!=" in m["after"] for m in pby.get("compare", [])) or any("!= 201" in m["before"] and "==" in m["after"] for m in pby.get("compare", [])))
check("python: a print becomes pass with the same indent", any(m["after"] == "pass" for m in pby.get("output", [])) and all(
      m["text"].split("\n")[m["line"] - 1].startswith((" " * 4, "pass")) for m in pby.get("output", [])))
check("python: each mutant is one line different, and compiles",
      all(sum(1 for a, b in zip(PY.split("\n"), m["text"].split("\n")) if a != b) == 1 for m in pm)
      and all(compile(m["text"], "x", "exec") for m in pm))
check("python: the covering tests of a python example are the python checks, not the bash house rules",
      "check_script_conventions.py" not in mp.covering_tests("Admin/API 2.0/python/python3/stCertificateExpiry.py")
      and any(t.startswith("test_python_") for t in mp.covering_tests("Admin/API 2.0/python/python3/stCertificateExpiry.py")))

# the progress file and the line that reads it
import json
import os
import tempfile
import time
sys.path.insert(0, str(ROOT / "tools"))
import mutation_progress as mpg  # noqa: E402
with tempfile.TemporaryDirectory() as _d:
    pf = os.path.join(_d, "progress.jsonl")
    os.environ["MUTATION_PROGRESS"] = pf
    mp.progress({"event": "start", "scripts": 2, "mutants": 20})
    mp.progress({"event": "script", "script": "Admin/x/a.py", "mutants": 12})
    for v in ["killed"] * 8 + ["survived"] * 2 + ["invalid"]:
        mp.progress({"event": "mutant", "script": "Admin/x/a.py", "verdict": v})
    lines = open(pf).read().splitlines()
    t0 = json.loads(lines[0])["t"]
    text = mpg.summarize(lines, now=t0 + 600)
    check("a progress file has a line for each step", len(lines) == 13 and all(json.loads(l)["event"] in {"start", "script", "mutant"} for l in lines))
    check("it says how far the run is, with what was caught, and which script it is on",
          "still running: 11 of 20 mutants (55%)" in text and "caught 8, survived 2, did not parse 1" in text and "now on script 1 of 2 (a.py, 11 of 12 mutants)" in text, text)
    check("it estimates the time left from the pace so far (a pause of minutes counts as 5)", "about 4 min left" in text, text)
    gap = [json.dumps({"event": "start", "scripts": 1, "mutants": 20, "t": 0}), json.dumps({"event": "script", "script": "a.py", "mutants": 20, "t": 1})]
    gap += [json.dumps({"event": "mutant", "script": "a.py", "verdict": "killed", "t": 10 + i}) for i in range(10)]
    gap += [json.dumps({"event": "mutant", "script": "a.py", "verdict": "killed", "t": 10 + 9 + 30000 + i}) for i in range(5)]   # eight hours later
    check("a night of sleep does not count as time spent", "about 2 min left" in mpg.summarize(gap, now=10 + 9 + 30000 + 4 + 1), mpg.summarize(gap, now=10 + 9 + 30000 + 5))
    mp.progress({"event": "end"})
    check("a finished run says so", mpg.summarize(open(pf).read().splitlines()).startswith("FINISHED:"))
    del os.environ["MUTATION_PROGRESS"]
    mp.progress({"event": "start", "scripts": 1, "mutants": 1})
    check("without MUTATION_PROGRESS nothing is written", len(open(pf).read().splitlines()) == 14)
    check("an empty file is said to be empty", "no run yet" in mpg.summarize([]))

# the time limit of a changed script
check("the limit is 4 times the baseline, at least 30 s and at most 4 minutes", mp.limit_for(2) == 30 and mp.limit_for(20) == 80 and mp.limit_for(900) == 240, (mp.limit_for(2), mp.limit_for(20), mp.limit_for(900)))
with tempfile.TemporaryDirectory() as _c:
    _chk = Path(_c) / "tests" / "offline" / "checks"
    _chk.mkdir(parents=True)
    (_chk / "test_endless.sh").write_text("#!/bin/bash\nwhile true; do :; done\n")
    (_chk / "test_fine.sh").write_text("#!/bin/bash\nexit 0\n")
    _t0 = time.time()
    _failed, _ = mp.run_tests(_c, ["test_endless.sh"], limit=2)
    check("a test that never ends is stopped at the limit and counted as a failure (a change that makes it endless is caught)", _failed and "hung" in _failed and time.time() - _t0 < 15, _failed)
    check("a test that passes returns no failure", mp.run_tests(_c, ["test_fine.sh"], limit=5)[0] is None)
print("test_mutation_probe: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
