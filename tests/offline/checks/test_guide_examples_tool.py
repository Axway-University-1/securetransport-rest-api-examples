#!/usr/bin/env python3
"""tools/guide_examples.py, which tests/online/checks/70.guides_examples.py uses: the curl examples of a guide, the method and path of each, the answer the
text says it gives, and why an example is not run. On a text made for the purpose, and on the real guides."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
import guide_examples as ge  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


CURL = 'curl -s -k -u "${ST_USER}:${ST_PASSWORD}" '
URL = '"https://${ST_SERVER}:${ST_PORT}/api/v2.0%s"'


def guide(*parts):
    """A guide text: each part is (command, text after it)."""
    out = ["# Title", "", "## First part", ""]
    for cmd, after in parts:
        out += ["```bash", cmd, "```", "", after, ""]
    return "\n".join(out)


def one(cmd, after):
    return ge.parse(guide((cmd, after)), "g.md")[0]


# the documented status, in several phrasings
for after, want in (("The answer is 200 with your own account.", "200"), ("The answer is `201`, with the address in the `Location` header.", "201"),
                    ("The call is answered 403.", "403"), ("A call with no credentials is refused with 401 (tried).", "401"),
                    ("The answer is 400, with \"Invalid start after date\".", "400"), ("It answers 204 and has no body.", "204"),
                    ("The same call answers 409 for a folder that exists.", "409")):
    e = one(CURL + URL % "/myself", after)
    check("documented status: '%s' -> %s" % (after[:48], want), e.documented == want, (e.documented, e.how))
e = one(CURL + URL % "/myself", "The answer shows your account. Not every resource has a HEAD (denied users answers `405`): look at the code.")
check("a status in brackets is an aside and is not the status of this example", e.documented == "2xx", (e.documented, e.how))
e = one(CURL + URL % "/myself", "The account has 17 entries and a page of 500.")
check("a number that is not a status, or has no word about the answer near it, is not taken", e.documented == "2xx" and e.how == "no documented status", (e.documented, e.how))
e = one(CURL + URL % "/myself", "On the lab, with 200 accounts, this returned 4 entries.")
check("200 accounts is not 'the answer is 200' (no word about the answer in that sentence is a status)", e.how != "the text says: On the lab, with 200 accounts, this returned 4 entries.", e.how)

# a text block after the example
t = guide(("%s%s" % (CURL, URL % "/version"), "```text\n{ \"version\" : \"5.5\" }\n```\n\nThe same path on the End User port answered 404."))
e = ge.parse(t, "g.md")[0]
check("a JSON answer that comes first is the answer of this example: 2xx, and the text after it is about another call (404)", e.documented == "2xx", (e.documented, e.how))
t = guide(("%s%s" % (CURL, URL % "/servers?fields=protocol"), "```text\n{ \"message\" : \"Error validating request\", \"validationErrors\" : [ \"Field protocol does not exist.\" ] }\n```"))
check("an error body that comes first means a 4xx", ge.parse(t, "g.md")[0].documented == "4xx")
t = guide(("%s%s" % (CURL, URL % "/myself"), "```text\nHTTP/1.1 401 Unauthorized\n```"))
check("an answer with its status line gives that status", ge.parse(t, "g.md")[0].documented == "401")
e = one(CURL + URL % "/myself", "")
check("no text: any 2xx, and flagged as not documented", e.documented == "2xx" and e.how == "no documented status")

# method and path
for cmd, method, path in ((CURL + URL % "/myself", "GET", "/myself"),
                          (CURL + "-X POST " + URL % "/accounts", "POST", "/accounts"),
                          (CURL + "-X PATCH " + URL % "/accounts/john", "PATCH", "/accounts/john"),
                          (CURL + "-X DELETE " + URL % "/files/docs", "DELETE", "/files/docs"),
                          (CURL + "-G " + URL % "/logs/transfers" + ' --data-urlencode "limit=1"', "GET", "/logs/transfers"),
                          (CURL + "-d '{}' " + URL % "/accounts", "POST", "/accounts"),
                          (CURL + "-I " + URL % "/accounts/john", "HEAD", "/accounts/john"),
                          (CURL + URL % "/accounts?limit=1&fields=name", "GET", "/accounts"),
                          (CURL + '-G -X POST ' + URL % "/servers/operations", "POST", "/servers/operations"),
                          (CURL + URL % "/daemons/operations?operation=start" + " \\\n  -X POST", "POST", "/daemons/operations")):
    e = one(cmd, "text")
    check("method and path of: %s" % cmd[len(CURL):][:60].replace("\n", " "), (e.method, e.path) == (method, path), (e.method, e.path))

# what is run and what is not
for cmd, reason in ((CURL + "-X POST " + URL % "/accounts", "writes"), (CURL + "-X DELETE " + URL % "/myself", "writes"),
                    (CURL + '"https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/files/docs"', "End User"),
                    (CURL + '-H "csrfToken: ${TOKEN}" ' + URL % "/myself", "needs the earlier step ($TOKEN)"),
                    (CURL + "-b session.jar " + URL % "/myself", "needs the earlier step (a file)"),
                    (CURL + "-X PUT -d @route.json " + URL % "/routes", "writes")):
    e = one(cmd, "text")
    why = ge.skip_reason(e)
    check("not run: %s -> %s" % (cmd[len(CURL):][:50].replace("\n", " "), reason), why is not None and reason in why, why)
check("a plain GET is run", ge.skip_reason(one(CURL + URL % "/myself", "text")) is None)
check("a GET with the five variables of the environment is run", ge.skip_reason(one(CURL + '-G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" --data-urlencode "limit=1" -H "Referer: x"', "text")) is None)

# only a block that starts with curl, and the heading and the index
t = "# Guide\n\n## Alpha\n\n```python\ncurl = 1\n```\n\n```bash\nls\n```\n\n```bash\ncurl -s https://${ST_SERVER}:${ST_PORT}/api/v2.0/a\n```\n\n## Beta\n\n```bash\ncurl -s https://${ST_SERVER}:${ST_PORT}/api/v2.0/b\n```\n"
ex = ge.parse(t, "g.md")
check("only a bash block that starts with curl is an example", len(ex) == 2, ex)
check("each has the heading it sits under, and the number in its guide", [(e.heading, e.index) for e in ex] == [("Alpha", 1), ("Beta", 2)], [(e.heading, e.index) for e in ex])

# the folder of guides can be another (a test of the check itself)
with tempfile.TemporaryDirectory() as d:
    (Path(d) / "stale.md").write_text(guide((CURL + URL % "/version", "The answer is 404.")))
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "guide_examples.py")], capture_output=True, text=True, env=dict(os.environ, ST_GUIDES_DIR=d))
    check("ST_GUIDES_DIR points the tool at another folder of guides", r.returncode == 0 and "stale.md" in r.stdout and "1 example(s); 1 would be run" in r.stdout, r.stdout + r.stderr)

# the real guides
real = ge.parse_all()
check("the guides have curl examples (more than 20)", len(real) > 20, len(real))
check("every example has a method and a path", all(e.method in ("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE") and e.path.startswith("/") for e in real),
      [e.label() for e in real if e.path == "?"])
check("some have a documented status", sum(1 for e in real if e.documented.isdigit()) >= 1)
check("some are run against the lab (they only read)", sum(1 for e in real if ge.skip_reason(e) is None) >= 10)
check("an example that writes is never run", all(ge.skip_reason(e) for e in real if e.method not in ("GET", "HEAD")))
check("every guide that has examples is found", {e.guide for e in real} >= {"time-formats.md", "reading-api-answers.md"})
check("the online check exists and uses the tool", "guide_examples" in (ROOT / "tests" / "online" / "checks" / "70.guides_examples.py").read_text())
print("test_guide_examples_tool: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
