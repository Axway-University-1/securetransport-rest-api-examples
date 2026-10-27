#!/usr/bin/env python3
"""Features/Guidance/changing-configuration.md: the structure it promises, and the jq and shell it shows, run offline against a small stand-in for
curl that keeps one object in a file and applies a PATCH (replace) or a PUT to it: the complete example (read, change, check, restore), the PUT
example (read, change the copy with jq, send it back), the jq that finds the position of a step, and the sed against jq demonstration."""
import json
import os
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


text = gc.read("changing-configuration.md")
check("the guide has the sections it promises", all(h in text for h in (
    "## PATCH or PUT", "## PATCH: the three operations", "## Lists, and route steps", "## PUT: send back the whole object",
    "## The server checks the whole object", "## Configuration options", "## A complete example: read, change, check, restore",
    "## Do not edit JSON with text substitution", "## Checklist")))
check("the answers it quotes are there", all(m in text for m in (
    'Missing field "nosuchfield"', "Array index 9 out of bounds", "415", "unknown / unsupported operation swap", "Cannot attach a route step to another route",
    "You must specify adminCertificateFileOrPath when certificateIssuer is set to other.", "Configuration options with name(s) No.Such.Option not found")))
check("it warns that remove leaves null and that a fragment resets what is left out", "still in the answer, now with the value `null`" in text
      and "**The two steps are gone.**" in text)

have_jq = shutil.which("jq") is not None
FAKE = r'''#!/usr/bin/env python3
# A stand-in for curl that keeps one object in state.json (cwd): GET prints it, PATCH applies replace operations, PUT replaces it.
import json, sys
a = sys.argv[1:]
method = "GET"; body = None; out = None
i = 0
while i < len(a):
    if a[i] == "-X": method = a[i + 1]; i += 2
    elif a[i] == "--data-binary":
        v = a[i + 1]; body = open(v[1:]).read() if v.startswith("@") else v; i += 2
    elif a[i] in ("-u", "-H"): i += 2
    else: i += 1
state = json.load(open("state.json"))
if method == "PATCH":
    for op in json.loads(body):
        assert op["op"] == "replace"
        node = state
        parts = op["path"].strip("/").split("/")
        for p in parts[:-1]: node = node[p]
        node[parts[-1]] = op["value"]
    json.dump(state, open("state.json", "w"))
elif method == "PUT":
    json.dump(json.loads(body), open("state.json", "w"))
else:
    print(json.dumps(state))
'''
if have_jq:
    d = tempfile.mkdtemp(prefix="cfg_guide_")
    try:
        Path(d, "curl").write_text(FAKE)
        os.chmod(Path(d, "curl"), 0o755)
        env = dict(os.environ, PATH=d + os.pathsep + os.environ["PATH"], ST_SERVER="h", ST_PORT="1", ST_USER="u", ST_PASSWORD="p")
        blocks = gc.blocks(text)

        # the complete example
        full = next(code for lang, code in blocks if lang == "bash" and code.lstrip().startswith("ACCOUNT=ZZTEST_example"))
        Path(d, "state.json").write_text(json.dumps({"name": "ZZTEST_example", "contact": {"email": "old@example.com", "phone": None}}))
        r = subprocess.run(["bash", "-c", full], cwd=d, env=env, capture_output=True, text=True)
        check("the complete example runs: it prints the new address and ends with 'the account is as it was'",
              r.returncode == 0 and "new@example.com" in r.stdout and "the account is as it was" in r.stdout, (r.returncode, r.stdout, r.stderr))
        check("... and the account holds the old address again", json.loads(Path(d, "state.json").read_text())["contact"]["email"] == "old@example.com")
        check("... and the patch it built is a list with a replace", json.loads(Path(d, "patch.json").read_text()) ==
              [{"op": "replace", "path": "/contact/email", "value": "new@example.com"}])

        # the PUT example: read, change the copy with jq, send the copy back, nothing else lost
        put = next(code for lang, code in blocks if lang == "bash" and "-X PUT" in code and "route_new.json" in code)
        put = put.replace("ROUTE_ID", "r1")
        Path(d, "state.json").write_text(json.dumps({"id": "r1", "name": "R", "description": None, "metadata": {"links": {}},
                                                      "steps": [{"id": "s1", "fileFilterExpression": "*.one"}, {"id": "s2", "fileFilterExpression": "*.two"}]}))
        r = subprocess.run(["bash", "-c", put], cwd=d, env=env, capture_output=True, text=True)
        now = json.loads(Path(d, "state.json").read_text())
        check("the PUT example changes the description and keeps the id, the metadata and the steps",
              r.returncode == 0 and now["description"] == "changed by a script" and now["id"] == "r1" and len(now["steps"]) == 2 and "metadata" in now, (r.stderr, now))

        # the jq that finds the position of a step
        idx = next(code for lang, code in blocks if lang == "bash" and "index(" in code).strip().replace("route.json", "state.json")
        Path(d, "state.json").write_text(json.dumps({"steps": [{"fileFilterExpression": "*.one"}, {"fileFilterExpression": "*.inserted"}, {"fileFilterExpression": "*.two"}]}))
        r = subprocess.run(["bash", "-c", idx], cwd=d, env=env, capture_output=True, text=True)
        check("jq finds the position of the step with a filter (2 of 0, 1, 2)", r.stdout.strip() == "2", (r.stdout, r.stderr))
    finally:
        shutil.rmtree(d, ignore_errors=True)

    # sed against jq
    demo = next(code for lang, code in gc.blocks(text) if lang == "bash" and code.lstrip().startswith("NEW="))
    r = subprocess.run(["bash", "-c", demo], capture_output=True, text=True)
    lines = r.stdout.strip().splitlines()
    check("sed makes text that is not JSON, and jq makes JSON", len(lines) == 2 and lines[0] == '{"name":"Smith "the boss" x Co"}'
          and json.loads(lines[1]) == {"name": 'Smith "the boss" & Co'}, (r.stdout, r.stderr))
    try:
        json.loads(lines[0])
        check("the sed output really is not JSON", False)
    except json.JSONDecodeError:
        check("the sed output really is not JSON", True)
else:
    print("  (jq is not installed: the jq snippets are not run)")

# the options example: values are a list of text, in a list of objects
opt = next(code for lang, code in gc.blocks(text) if lang == "bash" and "-X PUT" in code and "configurations/options" in code)
body = json.loads(opt.split("-d '")[1].split("'")[0])
check("the options example sends a list of objects with name and values (a list of text)",
      isinstance(body, list) and body[0]["name"] and all(isinstance(v, str) for v in body[0]["values"]), body)
print("test_guidance_changing_configuration: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
