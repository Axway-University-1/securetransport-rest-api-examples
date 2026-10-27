#!/usr/bin/env python3
"""Features/Guidance/expression-language-escaping.md: the structure it promises, and the escaping it teaches, run offline: the JSON layer of
each row of the worked table (json), the jq and python snippets, and the shell quoting cases (bash)."""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
import guide_checks as gc  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


NAME = "expression-language-escaping.md"
text = gc.read(NAME)
check("the guide has the sections it promises", all(h in text for h in (
    "## Where an expression goes, and where it does not", "## What the server does when the text is wrong", "## The three layers",
    "### Worked table", "## Write the body with a tool", "## The shell: single quotes", "## Checklist")))
check("the three server refusals for a wrong type are quoted", all(m in text for m in (
    "Valid steps.fileFilterExpressionType values are: GLOB, REGEXP, TEXT_FILES.", "The value specified by fileFilterExpressionType property is illegal.",
    "Unknown name value [GLOB] for enum class.")))
check("it says the server does not check the text of an expression", "The server does not check an expression when a route is saved" in text)

# the JSON layer of the worked table: the body text of each row, and what is stored when the server reads the JSON
base = '{"condition":"${transfer.target.matches(\'.*%s.txt\')}"}'
four, two, one = base % ("\\" * 4), base % ("\\" * 2), base % "\\"
check("four backslashes in the body: two are stored", json.loads(four)["condition"].count("\\") == 2)
check("two backslashes in the body: one is stored", json.loads(two)["condition"].count("\\") == 1)
try:
    json.loads(one)
    check("one backslash in the body is not valid JSON", False)
except json.JSONDecodeError:
    check("one backslash in the body is not valid JSON (the server answers 400 Incorrect JSON format)", True)
check("a plain regex filter: two in the body, one stored", json.loads('{"f":".*\\\\.(xml|txt)"}')["f"] == ".*\\.(xml|txt)")

# the snippets
blocks = gc.blocks(text)
py = next(b for lang, b in blocks if lang == "python")
ns = {}
out = subprocess.run([sys.executable, "-c", py], capture_output=True, text=True)
check("python: the snippet runs, and the body holds four backslashes", out.returncode == 0 and out.stdout.count("\\") == 4, (out.returncode, out.stdout, out.stderr))
exec(compile(py.split("print(body)")[0], "guide", "exec"), ns)
check("python: the EL text in memory has two backslashes, the body is valid JSON with two after reading",
      ns["el"].count("\\") == 2 and json.loads(ns["body"])["condition"].count("\\") == 2)

jq_block = next(code for lang, code in blocks if lang == "bash" and code.lstrip().startswith("EL=$(cat <<'EOF'"))
if shutil.which("jq"):
    d = tempfile.mkdtemp(prefix="el_guide_")
    try:
        r = subprocess.run(["bash", "-c", jq_block], cwd=d, capture_output=True, text=True)
        route = Path(d, "route.json")
        body = route.read_text() if route.exists() else ""
        check("jq: the snippet makes route.json with four backslashes in the body", r.returncode == 0 and body.count("\\") == 4, (r.returncode, r.stderr, body))
        check("jq: and the server would read two", json.loads(body)["condition"].count("\\") == 2 and json.loads(body)["conditionType"] == "EL")
    finally:
        shutil.rmtree(d, ignore_errors=True)
else:
    print("  (jq is not installed: the jq snippet is not run)")

# the shell: what the guide says about quotes
def sh(cmd):
    return subprocess.run(["bash", "-c", cmd], capture_output=True, text=True)


r = sh('echo "{\\"condition\\":\\"${transfer.target}\\"}"')
check("bash: ${...} in double quotes is a bad substitution", r.returncode != 0 and "bad substitution" in r.stderr, r.stderr)
r = sh('echo "{\\"condition\\":\\"${!empty account.email}\\"}"')
check("bash: ${!empty account.email} in double quotes is a bad substitution too", "bad substitution" in r.stderr, r.stderr)
r = sh("echo '{\"condition\":\"${!empty account.email}\"}'")
check("bash: the same text in single quotes is passed as it is", r.stdout.strip() == '{"condition":"${!empty account.email}"}', r.stdout)
r = sh('X=5; echo "{\\"n\\":\\"$X\\"} and \\${account.name}"')
check("bash: a backslash before ${ keeps it for EL, and $X is still expanded", r.stdout.strip() == '{"n":"5"} and ${account.name}', r.stdout)

print("test_guidance_expression_language_escaping: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
