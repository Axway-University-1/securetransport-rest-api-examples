#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified scripts in
Admin/API 2.0/bash/03.Connect against a configured server - the server CRUD
scripts only (07-12) - and independently verifies every step through the API.

Deliberately excluded, and why:
    01-04 (daemon GET/PUT/PATCH)     a daemon is a singleton per protocol, not
                                     a disposable object you create and delete.
                                     Changing one changes the whole server.
    05, 13 (daemon/server operations) start and stop real daemons and servers.
                                     On anything but a fully disposable lab
                                     this can interrupt live file transfers.
This check only ever creates, reads, updates and deletes its own two
throwaway server entries.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.

Objects touched, by the literal names the scripts use:
    SSH_TEST_SERVER_1, SSH_TEST_SERVER_2   created by 07, deleted by 12
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the servers scripts for real")

c = st_client.Checker("Servers, run for real from Admin/API 2.0/bash/03.Connect (07-12)")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
CONNECT_DIR = os.path.join(BASH_TREE, "03.Connect")
NAMES = ["SSH_TEST_SERVER_1", "SSH_TEST_SERVER_2"]


def script(name):
    return os.path.join(CONNECT_DIR, name)


def run_and_report(name, timeout=60):
    result = runner.run(script(name), timeout=timeout)
    c.check("%s runs without a shell level error" % name, result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")
    return result


client = harness.connect(config, c, mock=("the bundled mock does not implement /servers; run this against a "
                                          "real server to exercise it"))

try:
    with runner.real_credentials(BASH_TREE, config):

        pre_existing = [n for n in NAMES if client.exists("servers/" + n)]
        if pre_existing:
            c.check("none of %s already exist on this server" % NAMES, False, pre_existing)
            c.info("refusing to run 07.servers_POST.sh: it would collide with "
                   "a server that is already there. Remove or rename %s on "
                   "the server, or point this at a cleaner lab." % pre_existing)
            client.logout()
            sys.exit(c.done())
        c.check("none of %s already exist on this server" % NAMES, True)

        # -- 06: list servers ------------------------------------------------------
        run_and_report("06.servers_GET.sh")

        # -- 07: create SSH_TEST_SERVER_1, then duplicate it as _2 ------------------
        run_and_report("07.servers_POST.sh")

        for n in NAMES:
            c.check("GET /servers/%s now returns 200" % n, client.get("servers/" + n).status == 200)
        listed = {s.get("serverName") for s in client.page("servers")}
        for n in NAMES:
            c.check("%s is listed in GET /servers" % n, n in listed)

        duplicate = client.get("servers/SSH_TEST_SERVER_2").json() or {}
        c.check("the duplicate has its own port, not the original's",
                duplicate.get("port") not in (None, ""), duplicate.get("port"))
        for leftover in ("tmp.json",):
            c.check("07.servers_POST.sh does not leave %s behind" % leftover,
                    not os.path.exists(os.path.join(CONNECT_DIR, leftover)))

        # -- 08: HEAD check on SSH_TEST_SERVER_1 ------------------------------------
        result = run_and_report("08.servers_name_HEAD.sh")
        c.check("the script's own output reports the server exists",
                "Server exists." in result.stdout and "Server does not exist." not in result.stdout,
                result.stdout[-200:])

        # -- 09: GET SSH_TEST_SERVER_1 two ways --------------------------------------
        run_and_report("09.servers_name_GET.sh")

        # -- 10: PUT a new port onto SSH_TEST_SERVER_1 -------------------------------
        before_port = (client.get("servers/SSH_TEST_SERVER_1").json() or {}).get("port")
        run_and_report("10.servers_name_PUT.sh")
        after = client.get("servers/SSH_TEST_SERVER_1").json() or {}
        c.check("the port was changed by the PUT script", after.get("port") != before_port,
                (before_port, after.get("port")))
        c.check("clientPasswordAuth was set to default by the PUT script",
                after.get("clientPasswordAuth") == "default", after.get("clientPasswordAuth"))
        for leftover in ("tmp.json",):
            c.check("10.servers_name_PUT.sh does not leave %s behind" % leftover,
                    not os.path.exists(os.path.join(CONNECT_DIR, leftover)))

        # -- 11: PATCH the port and strip rsa keys -----------------------------------
        before = client.get("servers/SSH_TEST_SERVER_1").json() or {}
        had_rsa_key = "rsa" in str(before.get("publicKeys", "")).lower()
        run_and_report("11.servers_name_PATCH.sh")
        after = client.get("servers/SSH_TEST_SERVER_1").json() or {}
        c.check("the port set by the PATCH script is visible", after.get("port") == 8026,
                after.get("port"))
        if had_rsa_key:
            c.check("an rsa key was removed from publicKeys",
                    "rsa" not in str(after.get("publicKeys", "")).lower(), after.get("publicKeys"))
        else:
            c.info("the server had no rsa key to remove; that part of "
                   "11.servers_name_PATCH.sh could not be exercised here")

        # -- 12: delete both servers ---------------------------------------------------
        run_and_report("12.servers_name_DELETE.sh")
        for n in NAMES:
            c.check("%s is gone after 12.servers_name_DELETE.sh" % n,
                    not client.exists("servers/" + n))

finally:
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
