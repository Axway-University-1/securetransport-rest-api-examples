#!/usr/bin/env python3
"""
Read only. Runs the curl examples of the guides in Features/Guidance/ that only READ (GET and HEAD) against the configured server, and compares the HTTP status
with what the guide says. A guide that went stale after a product change (a call that now answers 400, a refusal that is now a 200) is found here, and the check
names the guide, the heading it sits under and the command.

What the guide says is read by tools/guide_examples.py from the text after each example: a status line, "The answer is 200", "is refused with 401", an answer
body that is an error. An example with no status in its text must answer a 2xx, and is listed as "no documented status". Only the status is compared, never
the numbers in the answer: they are the lab's, and change.

Not run, and listed with the reason:
  - an example that writes (POST, PUT, PATCH, DELETE): this check changes nothing on the server;
  - an example for the End User API (it needs an end user account);
  - an example that needs a step before it (a file, a variable the guide set in the text above it: a cookie jar, a token, an API key).

Needs no --write. With no tests/local/integration.conf it is a skip, like the other checks. Usage to see the list without a server:
    python3 tools/guide_examples.py
"""
import collections
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "common"))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
import st_client  # noqa: E402
import harness  # noqa: E402
import guide_examples as ge  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

c = st_client.Checker("The curl examples of the guides, run against the server: does each answer what its guide says?")

admin = harness.connect(config, c, mock="the guides' examples ask a real server: the bundled mock does not answer most of them")

env = dict(os.environ, ST_SERVER=str(config["st_server"]), ST_PORT=str(config["st_port"]),
           ST_USER=str(config["st_user"]), ST_PASSWORD=str(config["st_password"]))


def run(example):
    """(status, first part of the body) of the example, with curl made to print the status last. Runs in a folder of its own: an example may write a file."""
    code = re.sub(r"^\s*curl", "curl --max-time 60 -w '\\n%{http_code}'", example.code, count=1)
    with tempfile.TemporaryDirectory(prefix="guide_example_") as d:
        r = subprocess.run(["bash", "-c", code], capture_output=True, text=True, env=env, cwd=d, timeout=120)
    lines = [l for l in r.stdout.splitlines() if l.strip()]
    status = int(lines[-1]) if lines and lines[-1].strip().isdigit() else 0
    return status, "\n".join(lines[:-1])[:200].replace("\n", " ")


def matches(documented, status):
    if documented == "2xx":
        return 200 <= status < 300
    if documented == "4xx":
        return 400 <= status < 500
    return status == int(documented)


examples = ge.parse_all()
skipped = collections.defaultdict(list)
undocumented = []
ran = 0
try:
    for ex in examples:
        why = ge.skip_reason(ex)
        if why:
            skipped[why.split(" (")[0].split(":")[0]].append(ex)
            continue
        status, body = run(ex)
        ran += 1
        if ex.how == "no documented status":
            undocumented.append(ex)
        ok = matches(ex.documented, status)
        c.check("%s: the guide says %s, the server answered %d" % (ex.label(), ex.documented, status), ok,
                "the command: %s\n    the answer starts: %s" % (" ".join(ex.code.split())[:220], body))
finally:
    admin.logout()

per_guide = collections.Counter(e.guide for e in examples)
c.info("%d curl examples in %d guides: %d run against the server, %d not run" % (len(examples), len(per_guide), ran, len(examples) - ran))
for why, items in sorted(skipped.items()):
    c.info("not run, %s: %d (%s)" % (why, len(items), ", ".join(sorted({e.guide.replace('.md', '') for e in items}))))
if undocumented:
    c.info("%d example(s) have no status in their guide's text and were only checked for a 2xx: %s" % (
        len(undocumented), "; ".join(e.label() for e in undocumented[:8]) + (" ..." if len(undocumented) > 8 else "")))
sys.exit(c.done())
