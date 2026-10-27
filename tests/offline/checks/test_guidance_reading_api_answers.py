#!/usr/bin/env python3
"""Features/Guidance/reading-api-answers.md: the sections and the statements that must stay, and the code of the guide run on sample answers (the python
functions for results, errors and paging, and the jq filter for the two shapes of an operation). The curl examples are run by test_feature_guidance.py."""
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

for heading in ("## Summary", "## A 200 that says no", "## The shapes of an error", "## What happened, and what the API answers", "## Lists: counts and pages",
                "## Fewer fields: `fields=`", "## Does it exist? `HEAD`", "## A new object: the `Location` header", "## One call or a session", "## Checklist",
                "## What was not checked"):
    check("the guide has the section %s" % heading, heading in text)

for label, needle in (
        ("the two operations have two shapes", "The two answers have **different shapes**"),
        ("an empty answer is not a success", "An answer with no result is not a success"),
        ("the error shapes are listed: html, a string status, plain text", "`status` is a **string**"),
        ("a 405 has no Allow header", "A `405` has no `Allow` header"),
        ("a wrong checksum is a 500 and the retry warning", "A **wrong checksum is a `500`**"),
        ("sharing a missing folder answers 204", "**Sharing a folder that does not exist answers `204`.**"),
        ("a locked account looks like a wrong password", "**A locked account looks like a wrong password.**"),
        ("a page is 100 and limit=0 is not all", "`limit=0` gives the same 100: it does not mean \"all\""),
        ("limit=5000 timed out", "`limit=5000` did not answer within 30 seconds"),
        ("GET /files has no cap and no count", "Without `limit`, every entry is returned"),
        ("limit=0 on /files returns nothing", "**`limit=0` returned no entries.**"),
        ("/transfers is a plain list", "`GET /transfers` answers a plain list"),
        ("protocol cannot be named in fields", "Field protocol does not exist."),
        ("the End User API has no fields=", "**The End User API has no `fields=`.**"),
        ("the Location header", "`Location: https://host:port/api/v2.0/accounts/"),
        ("a new folder has no Location", "**A new folder** answered `201` with no `Location`"),
        ("POST /myself is a login", "`POST /myself` does not return the account"),
        ("what was not checked is listed", "The sporadic `500` on a correct upload")):
    check(label, needle in text, needle)

# the python snippets, in the order of the guide
def snippet(marker):
    return next(code for lang, code in blocks if lang == "python" and marker in code)


ns = {}
exec(compile(snippet("def results"), "guide", "exec"), ns)
exec(compile(snippet("def error_messages"), "guide", "exec"), ns)
exec(compile(snippet("def all_entries"), "guide", "exec"), ns)

server_no = {"serverStatuses": [{"serverName": "x", "message": "Server with name x does not exist.", "isSuccessful": False}]}
daemon_no = [{"daemon": "AS2", "message": "Can not start AS2 daemon", "isSuccessful": False}]
daemon_ok = [{"daemon": "FTP", "message": "Daemon FTP is started.", "isSuccessful": True}]
server_ok = {"serverStatuses": [{"serverName": "Ssh Default", "message": "started", "isSuccessful": True}]}
reference_form = {"daemonOperationResults": [{"daemon": "SSH", "message": "no", "isSuccessful": False}]}
check("results reads the object of a server operation and the bare list of a daemon operation, and the form of the reference",
      len(ns["results"](server_no)) == 1 and len(ns["results"](daemon_no)) == 1 and len(ns["results"](reference_form)) == 1)
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

# paging: a fake server with 1,234 entries, pages of 500 (and a page of exactly the size at the end)
def fake(total):
    data = list(range(total))

    def get(path, params):
        part = data[params["offset"]:params["offset"] + params["limit"]]
        return {"resultSet": {"returnCount": len(part), "totalCount": total}, "result": part}
    return get


check("all_entries reads 1234 entries in three calls", ns["all_entries"](fake(1234), "/x") == list(range(1234)))
check("all_entries stops on an exact multiple of the page (1000 in two full pages and an empty one)", ns["all_entries"](fake(1000), "/x") == list(range(1000)))
check("all_entries passes the filter on, and an empty list gives an empty list", ns["all_entries"](fake(0), "/x", {"name": "q"}) == [])

# jq: the filter of the guide, on the same samples
if shutil.which("jq"):
    jq_line = next(code for lang, code in blocks if lang == "bash" and code.lstrip().startswith("# every result"))
    filt = jq_line.split("jq -r ", 1)[1].strip().strip("'")
    def jq(doc):
        return subprocess.run(["jq", "-r", filt], input=json.dumps(doc), capture_output=True, text=True).stdout.strip()
    check("jq: the failure of a server operation", jq(server_no) == "x: Server with name x does not exist.", jq(server_no))
    check("jq: the failure of a daemon operation (a bare list)", jq(daemon_no) == "AS2: Can not start AS2 daemon", jq(daemon_no))
    check("jq: the reference form", jq(reference_form) == "SSH: no", jq(reference_form))
    check("jq: a success gives nothing", jq(daemon_ok) == "" and jq(server_ok) == "")
else:
    print("  (jq is not installed: its filter is not run)")

# the two tables of cases: every row has a status code of three digits in its second column
admin_t = text[text.index("### Admin API"):text.index("### End User API")]
eu_t = text[text.index("### End User API"):text.index("Three of these ask for care")]
for name, tab in (("Admin", admin_t), ("End User", eu_t)):
    rows = [l for l in tab.splitlines() if l.startswith("| ") and not l.startswith("| What you did") and not l.startswith("| ---")]
    codes = [l.split("|")[2].strip().strip("`") for l in rows]
    check("the %s table of cases has %d rows, each with a three digit code" % (name, len(rows)), len(rows) >= 9 and all(c.isdigit() and len(c) == 3 for c in codes), codes)
print("test_guidance_reading_api_answers: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
