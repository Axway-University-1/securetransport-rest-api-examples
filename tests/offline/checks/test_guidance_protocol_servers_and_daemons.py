#!/usr/bin/env python3
"""Features/Guidance/protocol-servers-and-daemons.md: the structure it promises, the measurements it quotes (consistent with each other), and the
bash it shows, run offline: the loop that waits for Running, against a stand-in for curl that answers GET /daemons from a list of statuses (and a
sleep that does not sleep), and the start example's check of isSuccessful."""
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


text = gc.read("protocol-servers-and-daemons.md")
check("the guide has the sections it promises", all(h in text for h in (
    "## Daemons and servers", "## Operations on a daemon", "### The `graceful` parameter", "## Operations on a server", "## How long it takes",
    "## The order, and waiting", "### A loop that waits for `Running`", "## A graceful stop goes on without you", "## What does not work",
    "## The confirmation words of the examples", "## Checklist")))
check("the messages it quotes are there", all(m in text for m in (
    "Daemon FTP is already started.", "Submitted graceful shutdown for daemon FTP.", "Not correct daemon type: nosuch. Possible values are: ftp, http, ssh, pesit or as2.",
    "Server with name No Such does not exist.", "The FTP daemon is not started. Start the daemon and try again.", "Invalid value for parameter name, expected (ssh)",
    'stopGracefully.arg1 must match "(?i)(stop)"', "Graceful shutdown in progress.")))
check("it says that a typo in graceful stops the daemon at once", "`graceful=maybe`" in text and "**Stopped the daemon at once.**" in text)
check("it says AS2 was left alone and what it quotes for it is marked as not tried", "AS2 was left alone" in text and "not tried here" in text)

# the measurements: the table has the four rounds, and in each a daemon comes before its server
rows = [r for r in text.splitlines() if re.match(r"\| (FTP, round \d|HTTP, one round) \|", r)]
check("the table of times has three FTP rounds and one HTTP round", len(rows) == 4, rows)
ok = True
for r in rows:
    cells = [c.strip() for c in r.strip("|").split("|")]
    nums = [float(re.search(r"([\d.]+) s", c).group(1)) for c in cells[1:5]]
    stop, start, daemon, server = nums
    ok = ok and start < 1 and daemon < server and 8 <= stop <= 16 and 10 <= daemon <= 13
check("in each round the start answers in under a second, the daemon is Running before its server is active, and the numbers are those of the summary", ok, rows)

# the loop that waits for Running
blocks = gc.blocks(text)
loop = next(code for lang, code in blocks if lang == "bash" and code.lstrip().startswith("# wait_daemon DAEMON"))
use = next(code for lang, code in blocks if lang == "bash" and code.lstrip().startswith("# start the daemon, check the answer"))
FAKE = r'''#!/usr/bin/env python3
# GET /daemons answers the next status of seq.txt (the last one stays); a POST answers a started daemon. calls.txt counts the GETs.
import json, sys
a = " ".join(sys.argv[1:])
if "-X POST" in a:
    print(json.dumps([{"daemon": "FTP", "message": "Daemon FTP is started.", "isSuccessful": "refuse" not in open("mode.txt").read()}]))
else:
    open("calls.txt", "a").write("x")
    lines = open("seq.txt").read().split()
    n = len(open("calls.txt").read())
    print(json.dumps({"ftpStatus": lines[min(n, len(lines)) - 1], "httpStatus": "Running"}))
'''
if shutil.which("jq"):
    d = tempfile.mkdtemp(prefix="daemon_guide_")
    try:
        Path(d, "curl").write_text(FAKE)
        Path(d, "sleep").write_text("#!/bin/bash\nexit 0\n")
        for n in ("curl", "sleep"):
            os.chmod(Path(d, n), 0o755)
        env = dict(os.environ, PATH=d + os.pathsep + os.environ["PATH"], ST_SERVER="h", ST_PORT="1", ST_USER="u", ST_PASSWORD="p")

        def run(seq, call, mode="ok", limit=None):
            Path(d, "seq.txt").write_text(seq)
            Path(d, "mode.txt").write_text(mode)
            for f in ("calls.txt",):
                if Path(d, f).exists():
                    Path(d, f).unlink()
            return subprocess.run(["bash", "-c", loop + "\n" + call], cwd=d, env=env, capture_output=True, text=True), len(Path(d, "calls.txt").read_text()) if Path(d, "calls.txt").exists() else 0

        r, polls = run("Not_running Not_running Running", "wait_daemon ftp 60; echo rc=$?")
        check("the loop returns 0 as soon as the status is Running, after 3 polls here", "rc=0" in r.stdout and polls == 3, (r.stdout, r.stderr, polls))
        r, polls = run("Running", "wait_daemon ftp 60; echo rc=$?")
        check("a daemon that is Running at once takes one poll", "rc=0" in r.stdout and polls == 1, (r.stdout, polls))
        r, polls = run("Not_running", "wait_daemon ftp 9; echo rc=$?")
        check("a daemon that never comes up: 1 after the limit, with the last status said, 3 polls for 9 seconds", "rc=1" in r.stdout and polls == 3
              and "not Running after 9 seconds (last status: Not_running)" in r.stderr, (r.stdout, r.stderr, polls))
        r, polls = run("Running", "wait_daemon http 60; echo rc=$?")
        check("the loop reads the status of the daemon it was given (http)", "rc=0" in r.stdout, (r.stdout, r.stderr))
        # the start example: it starts, checks isSuccessful, waits, and says so when the start was refused
        r, polls = run("Running", use.replace("ftp 60 && sleep 5", "ftp 60 && sleep 5; echo done"))
        check("the start example runs to its end when the start is accepted, and does not say it was refused", "done" in r.stdout and "refused" not in r.stdout, (r.stdout, r.stderr))
        r, polls = run("Running", use.replace("ftp 60 && sleep 5", "ftp 60 && sleep 5; echo done"), mode="refuse")
        check("... and says the start was refused when isSuccessful is false", "the start was refused" in r.stdout, (r.stdout, r.stderr))
    finally:
        shutil.rmtree(d, ignore_errors=True)
else:
    print("  (jq is not installed: the loop is not run)")

print("test_guidance_protocol_servers_and_daemons: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
