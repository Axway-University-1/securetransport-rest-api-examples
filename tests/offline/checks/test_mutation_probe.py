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
print("test_mutation_probe: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
