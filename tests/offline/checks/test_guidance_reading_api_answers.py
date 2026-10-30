#!/usr/bin/env python3
"""Features/Guidance/reading-api-answers.md: the sections and the statements that must stay, and the code of the guide run on sample answers (the python
functions for results and errors, and the jq filter for the two shapes of an operation). The curl examples are run by test_feature_guidance.py."""
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
import guide_checks as g  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


text = g.read("reading-api-answers.md")
blocks = g.blocks(text)

for heading in ("## Summary", "## A 200 that says no", "## The shapes of an error", "## Checklist"):
    check("the guide has the section %s" % heading, heading in text)
for removed in ("## One call or a session", "## Lists: counts and pages", "## What happened, and what the API answers"):
    check("the section %s is gone: it is a use case now" % removed, removed not in text)
for use_case in ("Admin/UseCases/06-lists-paging-and-fields", "EndUser/UseCases/08-lists-and-paging", "Admin/UseCases/04-stopping-and-starting-servers",
                 "Admin/UseCases/05-changing-an-object"):
    check("the guide links the use case %s" % use_case, use_case.split("/")[0] + "/UseCases/" + use_case.split("/")[-1] + "/README.md" in text.replace("../", ""))
    check("%s exists" % use_case, (g.ROOT / use_case / "README.md").exists())
check("the guide is short (under 120 lines)", len(text.splitlines()) < 120, len(text.splitlines()))
for label, needle in (
        ("the two operations have two shapes", "A daemon operation answers the list itself"),
        ("an empty answer is not a success", "an answer with no result is a failure"),
        ("the error shapes are listed: html, a string status, plain text", "`status` is a **string**"),
        ("a 405 has no Allow header", "A `405` has no `Allow` header")):
    check(label, needle in text, needle)

# the python snippets, in the order of the guide
def snippet(marker):
    return next(code for lang, code in blocks if lang == "python" and marker in code)


ns = {}
exec(compile(snippet("def unsuccessful"), "guide", "exec"), ns)
exec(compile(snippet("def error_messages"), "guide", "exec"), ns)

server_no = {"serverStatuses": [{"serverName": "x", "message": "Server with name x does not exist.", "isSuccessful": False}]}
daemon_no = [{"daemon": "AS2", "message": "Can not start AS2 daemon", "isSuccessful": False}]
daemon_ok = [{"daemon": "FTP", "message": "Daemon FTP is started.", "isSuccessful": True}]
server_ok = {"serverStatuses": [{"serverName": "Ssh Default", "message": "started", "isSuccessful": True}]}
reference_form = {"daemonOperationResults": [{"daemon": "SSH", "message": "no", "isSuccessful": False}]}
check("unsuccessful finds the failure in every shape", all(len(ns["unsuccessful"](a)) == 1 for a in (server_no, daemon_no, reference_form)))
check("unsuccessful is empty for a success, in both shapes", ns["unsuccessful"](daemon_ok) == [] and ns["unsuccessful"](server_ok) == [])
check("an answer with no result is reported as a failure", ns["unsuccessful"]([]) == [{"message": "the answer has no result"}]
      and len(ns["unsuccessful"]({"serverStatuses": []})) == 1)

samples = [
    (401, "Authentication required.", ["Authentication required."]),
    (401, '{ "message":"Unauthorized", "url":"https://h/api/v2.0/myself", "status":"401" }', ["Unauthorized"]),
    (401, "Login failed. Re-submit your credentials.  If this problem persists, contact your system administrator.",
     ["Login failed. Re-submit your credentials.  If this problem persists, contact your system administrator."]),
    (404, '{ "message": "Error validating request", "validationErrors": [ "Cannot find account with name x or it is not accessible" ], "docLink": "d" }',
     ["Cannot find account with name x or it is not accessible"]),
    (401, '{ "errors": [ { "code": "error.token.invalid", "detail": "Invalid token." } ] }', ["error.token.invalid: Invalid token."]),
    (400, "Invalid discriminator value. Check the schema for more information.", ["Invalid discriminator value. Check the schema for more information."]),
    (405, '{ "message": "HTTP 405 Method Not Allowed" }', ["HTTP 405 Method Not Allowed"]),
    (500, '{ "message":"Error while uploading file to location: /dir_a", "url":"u", "status":"500" }', ["Error while uploading file to location: /dir_a"]),
    (400, "[1, 2]", ["[1, 2]"]),
]
for status, body, expected in samples:
    got = ns["error_messages"](status, body)
    check("error_messages: %s %s" % (status, body[:46].replace("\n", " ")), got == expected, got)
check("error_messages: a success is not an error", ns["error_messages"](200, '{"message": "Logged in"}') == [] and ns["error_messages"](204, "") == [])

# jq: the filter of the guide, on the same samples
if shutil.which("jq"):
    jq_line = next(code for lang, code in blocks if lang == "bash" and code.lstrip().startswith("jq -r "))
    filt = jq_line.split("jq -r ", 1)[1].strip().strip("'")
    def jq(doc):
        return subprocess.run(["jq", "-r", filt], input=json.dumps(doc), capture_output=True, text=True).stdout.strip()
    check("jq: the failure of a server operation", jq(server_no) == "x: Server with name x does not exist.", jq(server_no))
    check("jq: the failure of a daemon operation (a bare list)", jq(daemon_no) == "AS2: Can not start AS2 daemon", jq(daemon_no))
    check("jq: the reference form", jq(reference_form) == "SSH: no", jq(reference_form))
    check("jq: a success gives nothing", jq(daemon_ok) == "" and jq(server_ok) == "")
else:
    print("  (jq is not installed: its filter is not run)")

print("test_guidance_reading_api_answers: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
