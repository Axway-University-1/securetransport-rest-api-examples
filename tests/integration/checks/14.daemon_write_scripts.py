#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified
Admin/API 2.0/bash/03.Connect/03.daemons_name_PUT.sh and
04.daemons_name_PATCH.sh against the real, live SSH daemon, then restores its
original configuration and verifies the restore - the daemon itself cannot
be created or deleted, so a round trip is the only safe pattern available.

Confirmed directly: /daemons/{name} only ever accepts "ssh" - every other
protocol name is rejected with a 400, regardless of which daemons exist or
are running on the server (see the gotchas skill). There is no "test daemon"
to redirect these two scripts at, the way 05.applications_scripts.py
redirects at a different application. This check touches the one daemon
this endpoint will ever address, briefly, and puts it back.

Also confirmed directly: GET /daemons/ssh on this server returns exactly
three fields - maxConnections, preferBouncyCastleProvider, banner - nothing
else. So the PUT script's three-field payload is a complete replacement of
this object, not a partial one that would silently drop other settings.

What this changes, briefly, before restoring it: maxConnections and banner on
the live SSH daemon. The scripts take the daemon, and the values, as arguments (they used to
default to ssh and fixed values, which changed a real daemon when run bare): 03 is run with
10, false and a banner, then with -10 (expected to be refused, exit 1, and not to take
effect); 04 changes maxConnections, preferBouncyCastleProvider and banner one by one. The
reference says a changed configuration takes effect when the daemon restarts, which nothing
here does. New SSH connections during the run are subject to whatever maxConnections is set to
at that moment; no call here drops already-established connections.

Also checked here, because none of it can change anything: that 03, 04 and 05 run with no
arguments exit 2 and send nothing, that 03 and 04 refuse another daemon than ssh (the server's
400 comes back as exit 1 and the daemon is unchanged), and that 05 refuses a stop without its
confirmation word. 05 is NEVER run with a daemon, an operation and the confirmation word on the
lab by this check: that stops the daemon (23.connect_operations_scripts.py does it, and is run
only on a lab one can restart). The statuses of the five daemons are compared before and after.

Refuses to run at all if the daemon cannot be read first - never proceeds
without a baseline to restore.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py. This
was deliberately excluded until the user running this suite explicitly asked
for it, understanding the above - see tests/integration/README.md.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the daemon PUT/PATCH scripts for real")

c = st_client.Checker("Daemon PUT/PATCH, run for real against the live SSH daemon, then restored")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
CONNECT_DIR = os.path.join(BASH_TREE, "03.Connect")

client = harness.connect(config, c, mock=("the bundled mock does not implement /daemons; run this against a "
                                          "real server to exercise it"))

response = client.get("daemons/ssh")
original = response.json() or {}
if response.status != 200 or not original:
    c.check("read the real SSH daemon's settings before changing anything", False,
            response.text[:200])
    c.info("refusing to run 03/04 without a baseline to restore afterward")
    client.logout()
    sys.exit(c.done())
c.check("read the real SSH daemon's settings before changing anything", True)
c.info("original: %s" % original)

statuses_before = client.get("daemons").json() or {}
BANNER = "This is a SecureTransport REST API test banner."


def daemon():
    return client.get("daemons/ssh").json() or {}


try:
    with runner.real_credentials(BASH_TREE, config):
        # -- run bare, or without what they need: exit 2, nothing sent ----------------------
        for script, args in (("03.daemons_name_PUT.sh", []), ("03.daemons_name_PUT.sh", ["ssh", "10", "false"]),
                             ("04.daemons_name_PATCH.sh", []), ("04.daemons_name_PATCH.sh", ["ssh", "maxConnections"]),
                             ("05.daemons_operations_POST.sh", []), ("05.daemons_operations_POST.sh", ["ssh"]),
                             ("05.daemons_operations_POST.sh", ["ssh", "stop"]),
                             ("05.daemons_operations_POST.sh", ["ssh", "stop", "stop-the-http-daemon"])):
            result = runner.run(os.path.join(CONNECT_DIR, script), args)
            c.check("%s %s exits 2" % (script, " ".join(args)), result.returncode == 2, (result.returncode, result.stdout[-200:]))
        c.check("and nothing was sent: the SSH daemon is as it was", daemon() == original, daemon())
        c.check("and every daemon has the status it had", (client.get("daemons").json() or {}) == statuses_before)

        # -- 03: PUT, run for real ---------------------------------------------------------------
        result = runner.run(os.path.join(CONNECT_DIR, "03.daemons_name_PUT.sh"), ["ssh", "10", "false", BANNER])
        c.check("03.daemons_name_PUT.sh ssh 10 false <banner> exits 0 and prints HTTP 204",
                result.returncode == 0 and "HTTP 204" in result.stdout,
                (result.returncode, result.stdout[-300:], result.stderr.strip()[-300:]))
        c.check("03 prints the old settings, and the command that puts them back",
                "The daemon ssh is now: " in result.stdout and "To put it back: ./03.daemons_name_PUT.sh ssh %s %s " % (
                    original["maxConnections"], str(original["preferBouncyCastleProvider"]).lower()) in result.stdout,
                result.stdout[-400:])

    after_put = client.get("daemons/ssh").json() or {}
    c.check("the valid PUT (maxConnections=10) took effect",
            after_put.get("maxConnections") == 10, after_put)
    c.check("the valid PUT's preferBouncyCastleProvider=false took effect",
            after_put.get("preferBouncyCastleProvider") is False, after_put)
    c.check("the valid PUT's banner took effect",
            after_put.get("banner") == "This is a SecureTransport REST API test banner.",
            after_put)

    with runner.real_credentials(BASH_TREE, config):
        # The invalid PUT: the server refuses it (400, the range is 1 to 100000), so the script exits 1
        result = runner.run(os.path.join(CONNECT_DIR, "03.daemons_name_PUT.sh"), ["ssh", "-10", "false", BANNER])
        c.check("the invalid PUT (maxConnections=-10) exits 1 and shows HTTP 400 and the server's reason",
                result.returncode == 1 and "HTTP 400" in result.stdout and "range from 1 to 100000" in result.stdout,
                (result.returncode, result.stdout[-300:]))
        c.check("the invalid PUT was rejected, not applied", daemon().get("maxConnections") == 10, daemon())

        # Another daemon than ssh: the server answers 400 on the read, so nothing is replaced
        result = runner.run(os.path.join(CONNECT_DIR, "03.daemons_name_PUT.sh"), ["http", "10", "false", BANNER])
        c.check("03.daemons_name_PUT.sh with the daemon http exits 1: the API only accepts ssh",
                result.returncode == 1 and "expected (ssh)" in result.stdout, (result.returncode, result.stdout[-300:]))
        result = runner.run(os.path.join(CONNECT_DIR, "04.daemons_name_PATCH.sh"), ["http", "maxConnections", "4"])
        c.check("04.daemons_name_PATCH.sh with the daemon http exits 1 too",
                result.returncode == 1 and "expected (ssh)" in result.stdout, (result.returncode, result.stdout[-300:]))
        c.check("and nothing changed", daemon() == after_put, daemon())

        for args, label in ((["ssh", "maxConnections", "4"], "maxConnections"),
                            (["ssh", "preferBouncyCastleProvider", "true"], "preferBouncyCastleProvider"),
                            (["ssh", "banner", "New banner"], "banner")):
            result = runner.run(os.path.join(CONNECT_DIR, "04.daemons_name_PATCH.sh"), args)
            c.check("04.daemons_name_PATCH.sh %s exits 0, prints the old value and HTTP 204" % " ".join(args),
                    result.returncode == 0 and "HTTP 204" in result.stdout and "The %s of ssh is now" % label in result.stdout
                    and "To put it back: ./04.daemons_name_PATCH.sh ssh %s " % label in result.stdout,
                    (result.returncode, result.stdout[-300:], result.stderr.strip()[-300:]))

        # A value the server refuses: exit 1, not applied
        result = runner.run(os.path.join(CONNECT_DIR, "04.daemons_name_PATCH.sh"), ["ssh", "maxConnections", "-1"])
        c.check("04.daemons_name_PATCH.sh ssh maxConnections -1 exits 1 and shows HTTP 400",
                result.returncode == 1 and "HTTP 400" in result.stdout, (result.returncode, result.stdout[-300:]))

    after_patch = client.get("daemons/ssh").json() or {}
    c.check("the PATCH to maxConnections took effect",
            after_patch.get("maxConnections") == 4, after_patch)
    c.check("the PATCH to preferBouncyCastleProvider took effect",
            after_patch.get("preferBouncyCastleProvider") is True, after_patch)
    c.check("the PATCH to banner took effect",
            after_patch.get("banner") == "New banner", after_patch)

finally:
    response = client.put("daemons/ssh", original)
    c.check("restored the SSH daemon to its original settings",
            response.status in (200, 204), response.status)
    restored_state = client.get("daemons/ssh").json() or {}
    c.check("the restored settings match what was there before this check ran",
            restored_state == original, restored_state)
    c.check("and every daemon still has the status it had",
            (client.get("daemons").json() or {}) == statuses_before)
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
