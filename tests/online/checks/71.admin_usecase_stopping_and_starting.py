#!/usr/bin/env python3
"""
STOPS AND STARTS THE FTP DAEMON of the server (and puts it back). Runs Admin/UseCases/04-stopping-and-starting-servers for real.

Only the ftp daemon is ever stopped: its name is the one constant of this check, and a script that is asked for another daemon is asked
only with a name it refuses (as2) or with something it cannot send. Nothing here names http (the End User API runs on it), ssh or pesit.
The check starts with a copy of GET /daemons and GET /servers, and ends by comparing them with what the server says then; its last step,
whatever happened before, starts the ftp daemon and its servers if they are not up.

What it proves, through its own session on the Admin API (not through what the scripts print):
  - 02 refused without the confirmation word, and with a GRACEFUL that is not true or false: the daemon is still Running afterwards.
  - 02 stops the daemon (the server answers isSuccessful true), and the other daemons are not touched; 03 waits for Not running; the server
    says the same (to another session, within a few seconds: the sessions do not agree at the same moment), and the ftp server is not active.
  - 04 starts it; 03 waits for Running; 05 waits for the server; the server says Running and active; 06 says nothing is different.
  - 06 finds a difference when the saved copy is changed (the copy only: no call changes the server for this), and says which.
  - 99 puts the daemon and its server back when a run leaves them stopped (02, 03 and then 99, with no 04), and is quiet when run twice.
  - 00.run_all.sh runs the whole way, leaves everything as at the start, and no state file.
  - What the server answers to a stop of a daemon that is stopped, and to a start of one that is running, is recorded (info lines).

Needs --write and st_allow_writes="yes". Takes about 3 minutes (the daemon is down for about 30 seconds three times): run it with
ST_CHECK_TIMEOUT=600. On the bundled mock it ends at once: the mock has no daemon operations.
"""
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

DAEMON = "ftp"          # the only daemon this check stops

config = st_client.load_config()
harness.require_writes(config, "stop and start the ftp daemon")

c = st_client.Checker("Admin use case 04, stopping and starting the ftp daemon, run for real")

ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
UC = runner.path("Admin", "UseCases", "04-stopping-and-starting-servers")
STATE_FILES = ("session.cookie.jar", "state.local.csrf", "state.local.daemons.json", "state.local.servers.json")

admin = harness.connect(config, c, mock="the bundled mock has no daemon operations; run this against a real server")


def daemons():
    return admin.get("daemons").json()


def servers():
    return sorted(({"protocol": s["protocol"], "serverName": s["serverName"], "isActive": s["isActive"]}
                   for s in admin.results("servers", {"fields": "serverName,isActive", "limit": 1000})), key=lambda s: s["serverName"])


def ftp_servers():
    return [s for s in servers() if s["protocol"] == DAEMON]


def status(daemon=DAEMON):
    return daemons().get(daemon + "Status")


def clear_local():
    for leftover in STATE_FILES:
        p = os.path.join(UC, leftover)
        if os.path.exists(p):
            os.remove(p)


def seconds_in(text, what):
    m = re.search(what + r".*?after about (\d+) seconds", text)
    return m.group(1) if m else "?"


def put_back():
    """Whatever happened: the ftp daemon Running and its servers active, as the copy at the start says."""
    if status() != "Running":
        harness.wait_until(lambda: status() == "Not running", 120, 3)   # a stop in progress
        admin.post("daemons/operations", None, params={"operation": "start", "daemon": DAEMON})
        harness.wait_until(lambda: status() == "Running", 120, 3)
    for s in ftp_servers():
        if s["serverName"] in {b["serverName"] for b in servers_before if b["isActive"]} and not s["isActive"]:
            harness.wait_until(lambda: all(x["isActive"] for x in ftp_servers()), 60, 3)
            if not all(x["isActive"] for x in ftp_servers()):
                admin.post("servers/operations", None, params={"serverName": s["serverName"], "operation": "start"})
                harness.wait_until(lambda: all(x["isActive"] for x in ftp_servers()), 120, 3)


daemons_before = daemons()
servers_before = servers()
c.info("at the start: %s" % ", ".join("%s %s" % (k.replace("Status", ""), v) for k, v in sorted(daemons_before.items())))
c.info("the ftp servers at the start: %s" % ", ".join("%s %s" % (s["serverName"], "active" if s["isActive"] else "not active") for s in ftp_servers()))

armed = False   # put_back() runs only once the check has begun to change something
try:
    if daemons_before.get(DAEMON + "Status") != "Running" or not ftp_servers() or not all(s["isActive"] for s in ftp_servers()):
        c.info("the ftp daemon is not Running, or it has no server, or one is not active: this check will not stop it")
        sys.exit(c.done())
    armed = True

    with runner.real_credentials(ADMIN_TREE, config):
        def script(name, *args, timeout=240):
            return runner.run(os.path.join(UC, name), list(args), timeout=timeout)

        def out(r):
            return (r.stdout + r.stderr).strip()

        # ---- 01: look, and keep a copy ------------------------------------------------------------------------------
        r = script("01.daemons_GET.sh")
        c.check("01 exits 0", r.returncode == 0, out(r)[-300:])
        c.check("01 names the ftp daemon and its status", "ftp\tRunning" in r.stdout, r.stdout[-300:])
        for f in ("state.local.daemons.json", "state.local.servers.json"):
            c.check("01 saved %s" % f, os.path.getsize(os.path.join(UC, f)) > 2 if os.path.exists(os.path.join(UC, f)) else False)
        saved = json.load(open(os.path.join(UC, "state.local.daemons.json")))
        c.check("01 saved what the server says: the daemons", saved == daemons_before, (saved, daemons_before))
        c.check("01 saved the servers, sorted by name, as the server has them",
                json.load(open(os.path.join(UC, "state.local.servers.json"))) == servers_before)
        r = script("06.compare_with_start.sh")
        c.check("06 right after 01 says nothing is different (exit 0)", r.returncode == 0 and "Nothing is different" in r.stdout, out(r)[-300:])

        # ---- 02: refused before any call ----------------------------------------------------------------------------
        r = script("02.daemon_stop.sh", DAEMON)
        c.check("02 with no confirmation word exits 2", r.returncode == 2 and "give the word stop-the-ftp-daemon" in r.stdout, out(r)[-300:])
        r = script("02.daemon_stop.sh", DAEMON, "stop-the-ssh-daemon")
        c.check("02 with the word of another daemon exits 2", r.returncode == 2, out(r)[-300:])
        r = script("02.daemon_stop.sh", DAEMON, "stop-the-ftp-daemon", "yes")
        c.check("02 with GRACEFUL yes exits 2 (the server would take it: this script does not)", r.returncode == 2 and "it must be true or false" in r.stdout, out(r)[-300:])
        c.check("the ftp daemon is still Running after the refusals", status() == "Running", status())
        r = script("03.daemon_wait.sh", DAEMON, "Stopped")
        c.check("03 with a state the server never gives exits 2", r.returncode == 2, out(r)[-300:])
        r = script("03.daemon_wait.sh", DAEMON, "Not running", "3")
        c.check("03 waits 3 seconds for Not running on a daemon that is Running, and exits 1", r.returncode == 1 and "last status: Running" in r.stdout, out(r)[-300:])

        # ---- 02, 03: the stop ---------------------------------------------------------------------------------------
        r = script("02.daemon_stop.sh", DAEMON, "stop-the-ftp-daemon", "true")
        c.check("02 stops the ftp daemon (exit 0)", r.returncode == 0 and "(isSuccessful: true)" in r.stdout, out(r)[-300:])
        c.check("02 says the answer is not the stop", "That is not the same as stopped" in r.stdout, r.stdout[-200:])
        r = script("03.daemon_wait.sh", DAEMON, "Not running", "120")
        c.check("03 sees the daemon Not running (exit 0)", r.returncode == 0, out(r)[-300:])
        c.info("the stop: the daemon said Not running after about %s seconds" % seconds_in(r.stdout, "Not running"))
        lag = time.time()
        c.check("another session says the ftp daemon is Not running (within 30 seconds)", bool(harness.wait_until(lambda: status() == "Not running", 30, 1)), status())
        c.info("another session read Not running %.0f seconds after step 03 did" % (time.time() - lag))
        now = daemons()
        c.check("the other daemons are as they were (http, pesit, ssh, as2)",
                all(now.get(k) == v for k, v in daemons_before.items() if k != DAEMON + "Status"), (now, daemons_before))
        c.check("the ftp server is not active while its daemon is down", not any(s["isActive"] for s in ftp_servers()), ftp_servers())
        r = script("02.daemon_stop.sh", DAEMON, "stop-the-ftp-daemon")
        c.check("02 on a daemon that is already stopped sends nothing and exits 0", r.returncode == 0 and "already stopped" in r.stdout, out(r)[-300:])
        r = script("06.compare_with_start.sh")
        c.check("06 finds the ftp daemon (and its server) different, and exits 1",
                r.returncode == 1 and "DIFFERENT: the ftp daemon was Running and is Not running" in r.stdout
                and "DIFFERENT: the server Ftp Default was active and is not active" in r.stdout, out(r)[-400:])
        raw = admin.post("daemons/operations", None, params={"operation": "stop", "daemon": DAEMON, "graceful": "true"})
        c.info("what the server answers to a stop of the stopped daemon: HTTP %s %s" % (raw.status, raw.text.replace("\n", " ")[:200]))
        time.sleep(20)
        c.info("20 seconds after that stop of a stopped daemon, the ftp daemon says: %s" % status())

        # ---- 04, 03, 05: the start ----------------------------------------------------------------------------------
        r = script("04.daemon_start.sh", DAEMON)
        c.check("04 starts the ftp daemon (exit 0)", r.returncode == 0 and "(isSuccessful: true)" in r.stdout, out(r)[-300:])
        r = script("03.daemon_wait.sh", DAEMON, "Running", "120")
        c.check("03 sees the daemon Running (exit 0)", r.returncode == 0, out(r)[-300:])
        c.info("the start: the daemon said Running after about %s seconds (from the start of 03)" % seconds_in(r.stdout, "Running"))
        lag = time.time()
        c.check("another session says the ftp daemon is Running (within 30 seconds: it can still say Not running for a few seconds after step 03 saw Running)",
                bool(harness.wait_until(lambda: status() == "Running", 30, 1)), status())
        c.info("another session read Running %.0f seconds after step 03 did" % (time.time() - lag))
        r = script("05.servers_wait.sh", DAEMON, "60")
        c.check("05 sees the ftp servers active (exit 0)", r.returncode == 0 and "are active" in r.stdout, out(r)[-300:])
        c.info("the servers: %s" % [l for l in r.stdout.splitlines() if "are active" in l or "did not come up" in l])
        c.check("the server says every ftp server is active", all(s["isActive"] for s in ftp_servers()), ftp_servers())
        r = script("04.daemon_start.sh", DAEMON)
        c.check("04 on a daemon that is Running sends nothing and exits 0", r.returncode == 0 and "already running" in r.stdout, out(r)[-300:])
        raw = admin.post("daemons/operations", None, params={"operation": "start", "daemon": DAEMON})
        c.info("what the server answers to a start of the running daemon: HTTP %s %s" % (raw.status, raw.text.replace("\n", " ")[:200]))
        r = script("06.compare_with_start.sh")
        c.check("06 says everything is as at the start (exit 0)", r.returncode == 0 and "Nothing is different" in r.stdout, out(r)[-300:])
        c.check("the servers and the daemons are exactly what the check saw at the start", servers() == servers_before and daemons() == daemons_before)

        # 06 reads a copy: change the copy (a file), not the server
        copy = os.path.join(UC, "state.local.servers.json")
        original = open(copy).read()
        try:
            changed = json.loads(original)
            for s in changed:
                if s["protocol"] == DAEMON:
                    s["isActive"] = False
            json.dump(changed, open(copy, "w"))
            r = script("06.compare_with_start.sh")
            c.check("06 finds a difference in the copy: exit 1 and the server named",
                    r.returncode == 1 and "DIFFERENT: the server Ftp Default was not active and is active" in r.stdout, out(r)[-300:])
        finally:
            open(copy, "w").write(original)

        # ---- 99: put back what a run left stopped ---------------------------------------------------------------------
        r = script("02.daemon_stop.sh", DAEMON, "stop-the-ftp-daemon", "true")
        c.check("02 stops the daemon again, for the cleanup to find it", r.returncode == 0, out(r)[-300:])
        r = script("03.daemon_wait.sh", DAEMON, "Not running", "120")
        c.check("03 sees it Not running", r.returncode == 0, out(r)[-300:])
        started = time.time()
        r = script("99.cleanup_DELETE.sh", DAEMON, timeout=400)
        c.check("99 starts the daemon that was Running at the start and waits for it (exit 0)",
                r.returncode == 0 and "was Running at the start and is: Not running. Starting it..." in r.stdout and "Cleaned up." in r.stdout, out(r)[-500:])
        c.info("99 put the daemon and its servers back in %d seconds" % (time.time() - started))
        c.check("the server says the ftp daemon is Running and its servers active after 99", status() == "Running" and all(s["isActive"] for s in ftp_servers()),
                (status(), ftp_servers()))
        c.check("99 removed the copy, the session jar and the token", not any(os.path.exists(os.path.join(UC, f)) for f in STATE_FILES))
        r = script("99.cleanup_DELETE.sh", DAEMON)
        c.check("99 a second time, with nothing to put back, exits 0", r.returncode == 0 and "There is no saved copy of the start" in r.stdout, out(r)[-300:])
        r = script("99.cleanup_DELETE.sh", "as2")
        c.check("99 never touches as2: it is refused (exit 2)", r.returncode == 2, out(r)[-300:])
        r = script("00.run_all.sh", "as2")
        c.check("00 refuses as2 (exit 2) before any call", r.returncode == 2 and "===" not in r.stdout, out(r)[-300:])
        r = script("06.compare_with_start.sh")
        c.check("06 with the copy gone says so and exits 1", r.returncode == 1 and "run 01.daemons_GET.sh first" in r.stdout, out(r)[-300:])
        clear_local()

        # ---- 00: the whole run -------------------------------------------------------------------------------------
        r = script("00.run_all.sh", DAEMON, timeout=500)
        c.check("00 the whole use case, 01 to 06 and the cleanup, exits 0", r.returncode == 0, out(r)[-600:])
        for name in ("01.daemons_GET", "02.daemon_stop", "03.daemon_wait", "04.daemon_start", "05.servers_wait", "06.compare_with_start", "99.cleanup_DELETE"):
            c.check("00 ran %s" % name, "=== %s ===" % name in r.stdout, r.stdout[-200:])
        c.check("00 ends with the proof and the cleanup", "Nothing is different: every daemon and every server is as at the start." in r.stdout and "Cleaned up." in r.stdout, r.stdout[-300:])
        c.check("00 left no state file", not any(os.path.exists(os.path.join(UC, f)) for f in STATE_FILES))

    c.check("every daemon is as at the start", daemons() == daemons_before, (daemons(), daemons_before))
    c.check("every server is as at the start", servers() == servers_before, (servers(), servers_before))
finally:
    try:
        if armed:
            put_back()
    except st_client.STError as e:
        c.info("could not put the ftp daemon back: %s. DO IT BY HAND: POST /daemons/operations?operation=start&daemon=ftp" % e)
    clear_local()
    admin.logout()

sys.exit(c.done())
