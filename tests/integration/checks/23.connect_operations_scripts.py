#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified
03.Connect/05.daemons_operations_POST.sh and 13.servers_operations_POST.sh
against a configured server - the two scripts this project had excluded as
"disruptive" because they start and stop real daemons and servers - then
restores every daemon and server this check touches to its original state
and verifies the restore.

This needed, and got, an explicit, informed decision before it was added:
05 really does stop the live http daemon (forcefully) and gracefully stop
the live ssh daemon (up to a 600 second timeout) on whatever server this
runs against.

Confirmed directly while building this, and worth knowing before assuming
the two scripts are equally disruptive: 13.servers_operations_POST.sh is NOT
a stop script at all - it only starts a server or daemon that is already
found not running, and does nothing to anything already active. Run on its
own, against a server where everything is already up, it is a safe no-op
that only reports status. It correctly starts back up anything 05 just
stopped (http, ssh) - but it does also *attempt* to start this server's own
AS2 daemon and "As2 Default" server, both intentionally off before this
check touched anything. Confirmed directly, that attempt cannot succeed
regardless: `POST /daemons/operations?operation=start&daemon=as2` returns
`isSuccessful: false`, `"the default server As2 Default is not enabled"` -
the AS2 listener is disabled at the server's persistent configuration, a
different and more durable setting than the running/stopped toggle
start/stop affects, and 13's own script never checks the response to notice.
There was accordingly never any real risk of this check leaving AS2 enabled
- but this check still explicitly puts it back to stopped/inactive in its
own cleanup regardless, as a defensive belt-and-suspenders measure, using
`operation=stop` on /servers/operations, confirmed directly to work the same
way `operation=start` already does (13's own real call) - neither stop is
demonstrated in any one shipped script for servers.

Also fixes a real, standing mischaracterisation in this project's own
history: 13 was grouped with 05 as "starting and stopping real daemons and
servers" when it was first excluded - it never stops anything at all.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.
"""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the Connect operations scripts for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Connect operations, run for real from Admin/API 2.0/bash/03.Connect")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
CONNECT_DIR = os.path.join(BASH_TREE, "03.Connect")
DAEMON_PROTOCOLS = ("ftp", "http", "pesit", "ssh", "as2")


def daemon_statuses(client):
    daemons = client.get("daemons").json() or {}
    return {p: daemons.get(p + "Status") for p in DAEMON_PROTOCOLS}


def server_states(client):
    return {s["serverName"]: s["isActive"]
            for s in client.page("servers", params={"fields": "serverName,isActive"})}


def wait_until(predicate, timeout=90, interval=3):
    """
    Confirmed directly, a real (if transient) failure mode: stopping and
    restarting daemons/servers can make the admin API itself briefly
    unreachable, and a bare connection error from one predicate call used to
    propagate straight out of this loop and crash the whole check, even
    though every attempt afterward would have succeeded. Treat a transient
    STError the same as a predicate that simply is not true yet.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if predicate():
                return True
        except st_client.STError:
            pass
        time.sleep(interval)
    try:
        return predicate()
    except st_client.STError:
        return False


client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /daemons or /servers operations; "
           "run this against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

original_daemons = daemon_statuses(client)
original_servers = server_states(client)
c.info("original daemon statuses: %s" % original_daemons)
c.info("original server states: %s" % original_servers)

try:
    with runner.real_credentials(BASH_TREE, config):
        result = runner.run(os.path.join(CONNECT_DIR, "05.daemons_operations_POST.sh"), timeout=90)
        c.check("05.daemons_operations_POST.sh runs without a shell level error",
                result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")

    stopped = wait_until(lambda: daemon_statuses(client)["http"] == "Not running"
                        and daemon_statuses(client)["ssh"] == "Not running")
    after_stop = daemon_statuses(client)
    c.check("http and ssh daemons are Not running after 05's own stop calls",
            stopped, after_stop)

    with runner.real_credentials(BASH_TREE, config):
        result = runner.run(os.path.join(CONNECT_DIR, "13.servers_operations_POST.sh"), timeout=90)
        c.check("13.servers_operations_POST.sh runs without a shell level error",
                result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")

    started = wait_until(lambda: all(v == "Running" for k, v in daemon_statuses(client).items()
                                     if original_daemons[k] == "Running"))
    after_start = daemon_statuses(client)
    c.check("every daemon that was Running originally is Running again after 13",
            started, after_start)

    servers_reactivated = wait_until(
        lambda: all(server_states(client).get(name) for name, was_active
                   in original_servers.items() if was_active))
    c.check("every server that was active originally is active again after 13",
            servers_reactivated, server_states(client))

    # 13 DOES attempt to start as2 as a side effect - confirmed directly, it
    # is silently unsuccessful. The AS2 listener is disabled at the server
    # configuration level ("the default server As2 Default is not enabled" -
    # a persistent setting, distinct from the running/stopped state
    # start/stop toggle), so 13's attempt cannot bring it up regardless.
    # There was never any real risk of this check leaving AS2 enabled.
    c.check("as2 stays Not running - 13's start attempt cannot override a disabled listener",
            daemon_statuses(client)["as2"] == "Not running", daemon_statuses(client))
    c.check('"As2 Default" stays inactive for the same reason',
            server_states(client).get("As2 Default") is False, server_states(client))

finally:
    # Put AS2 back exactly the way this check found it, if it was not
    # supposed to be running - the one piece no shipped script does.
    if original_daemons.get("as2") == "Not running":
        as2_server_name = next((name for name in original_servers if "As2" in name), None)
        if as2_server_name and original_servers.get(as2_server_name) is False:
            response = client._request(
                "POST", "servers/operations?serverName=%s&operation=stop"
                % as2_server_name.replace(" ", "%20"))
            c.check("restored %s to inactive: request accepted" % as2_server_name,
                    response.status == 200, response.text[:200])
        response = client._request(
            "POST", "daemons/operations?operation=stop&daemon=as2&graceful=false")
        c.check("restored the as2 daemon to stopped: request accepted",
                response.status == 200, response.text[:200])
        wait_until(lambda: daemon_statuses(client)["as2"] == "Not running")

    # The daemons and servers come back asynchronously, after the last
    # request: give them time to settle before comparing, rather than compare
    # the first snapshot
    wait_until(lambda: daemon_statuses(client) == original_daemons
               and server_states(client) == original_servers)
    try:
        final_daemons = daemon_statuses(client)
        final_servers = server_states(client)
    except st_client.STError as e:
        final_daemons = final_servers = "no answer: %s" % e
    c.check("every daemon matches its original status", final_daemons == original_daemons,
            (original_daemons, final_daemons))
    c.check("every server matches its original active state",
            final_servers == original_servers, (original_servers, final_servers))
    try:
        client.logout()
    except st_client.STError:
        pass

c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
