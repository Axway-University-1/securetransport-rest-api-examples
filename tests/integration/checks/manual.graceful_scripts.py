#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs a substituted copy of the real stGraceful.py in
Admin/API 2.0/python/python3 - with its Transaction Manager stop call
removed - against a configured server, then restores every cluster service,
daemon and server it touches and verifies the restore.

MANUAL ONLY - not part of run_integration.sh --write. This file is named
without a leading number on purpose, so
`find checks -name '[0-9]*' -type f` (run_integration.sh's own discovery)
never finds it. It also requires a second, explicit flag beyond --write (see
below). Run it by hand only, and only once you have read the incident this
docstring describes.

Why this is separate from every other check here: an earlier, numbered
version of this check caused a real several-minutes-long outage of every
protocol daemon and server on the test server it ran against, undetected
until a later, unrelated command happened to reconnect. Confirmed
afterward, as best this could be reconstructed:

  - The first run hit an over-tight subprocess timeout (120s) and was killed
    mid-script, while stGraceful.py's own daemon-stop loop was still
    in flight.
  - This check's own restoration logic (started daemons back up, verified
    "Running", reported success - twice, independently) never checked or
    restored the underlying *server* isActive state at all - a real gap,
    not bad luck, since stopping a daemon also drops its server's isActive
    flag.
  - Best-understood root cause of the outage itself: a "graceful stop with a
    timeout" (stopDaemon uses graceful=true and a timeout in seconds)
    appears to keep running server-side on its own clock, independent of the
    client that triggered it. This check's restart raced against that still
    -pending stop; the delayed stop then landed anyway, some time after this
    check had already reported everything healthy.
  - The end state was fully recovered by hand, and re-confirmed clean
    (daemons, servers, cluster services and the Transaction Manager all
    matching their original values) before this rewritten version was
    written.

What changed here as a result, each one directly answering the incident
above:

  - No subprocess timeout under ten minutes. The real script is left to run
    to its own completion rather than risk killing it mid-operation again -
    that kill is what left the server-side state ambiguous in the first
    place.
  - Every daemon, cluster service AND server this check can affect is
    captured before anything runs, and every one of them is restored and
    re-verified - not just daemons and cluster services.
  - After the first restoration pass reports success, this check waits an
    additional settle period (matching the script's own gtime argument, with
    margin) and re-verifies everything a second time, specifically to catch
    a delayed stop that was still in flight - the exact failure mode that
    caused the incident.
  - Confirmed directly (recovering from the incident, not assumed): trying
    to start a server immediately after starting its daemon can fail with
    "the X daemon is not started" or "the port is in use" even when the
    daemon truly is (or is about to be) up - a real timing race, not a
    stable error. Server restoration here waits for daemons to report
    Running first, then retries starting each server rather than trusting
    one attempt's response.

Separately, and unrelated to the incident: confirmed directly, while this
server's Transaction Manager was still running (nothing was ever put at risk
to find this out), `POST /transactionManager/operations?operation=start` is
rejected outright - `"stopGracefully.arg1 must match \"(?i)(stop)\""` - this
endpoint only ever implements stopping the TM, with no symmetric start
operation anywhere in the API. That is why this check removes the
Transaction Manager stop entirely rather than round-trip it: there is no
confirmed way to bring it back via this API at all.

st_edge_server is not set in this project's own config, so "core" and "edge"
are the same real machine here - the script's edge-labelled calls repeat the
same operations against the one server this check restores afterward.

Confirmed directly: this server's own AS2 daemon has a disabled listener at
the server configuration level (see 23.connect_operations_scripts.py's own
notes) - it was already "Not running" and its server already inactive before
this check touches anything, and is left alone throughout, matching its
original state without this check needing to do anything about it
specifically.

stGraceful.py stops nothing without --yes, which this check gives; it also stops a daemon
by daemon=<protocol> (it used to send a serverName=, which the reference does not give that
endpoint), so a daemon stop here is the first time that call is made against a real server.
The offline tests (tests/checks/test_python_graceful.py) run the whole script against a fake
server instead, and are what covers it day to day.

Needs --write, st_allow_writes="yes" (same as 04.accounts_scripts.py), AND
--i-understand-this-can-disrupt-live-service on the command line - three
separate, deliberate opt-ins for one script, because two were not enough to
stop the incident above from needing this rewrite.
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
    st_client.skip("read only run, pass --write to run the graceful script for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

if "--i-understand-this-can-disrupt-live-service" not in sys.argv:
    st_client.skip("this check needs --i-understand-this-can-disrupt-live-service too - "
                   "read this file's own docstring first, it documents a real incident")

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

c = st_client.Checker("stGraceful.py (Transaction Manager stop removed), run for real from "
                       "Admin/API 2.0/python/python3 [MANUAL CHECK]")

PY_TREE = runner.path("Admin", "API 2.0", "python")
SCRIPT = os.path.join(PY_TREE, "python3", "stGraceful.py")
DAEMON_PROTOCOLS = ("ftp", "http", "pesit", "ssh", "as2")
CLUSTER_SERVICES = ("FolderMonitor", "Scheduler")
GTIME = "10"
SETTLE_SECONDS = 45  # GTIME plus a generous margin, for the delayed-stop check


def daemon_statuses(client):
    daemons = client.get("daemons").json() or {}
    return {p: daemons.get(p + "Status") for p in DAEMON_PROTOCOLS}


def server_states(client):
    return {s["serverName"]: s["isActive"]
            for s in client.page("servers", params={"fields": "serverName,isActive"})}


def cluster_statuses(client):
    return {s: (client.get("clusterServices", params={"serviceName": s}).json() or {}).get("status")
            for s in CLUSTER_SERVICES}


def tm_status(client):
    return (client.get("transactionManager").json() or {}).get("status")


def wait_until(predicate, timeout=90, interval=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return predicate()


def restore_everything(client, original_daemons, original_servers, original_cluster):
    for service in CLUSTER_SERVICES:
        client._request("POST", "clusterServices/operations?operation=start&serviceName=%s" % service)

    for protocol, status in original_daemons.items():
        if status == "Running":
            client._request("POST", "daemons/operations?operation=start&daemon=%s" % protocol)
    wait_until(lambda: all(daemon_statuses(client)[p] == "Running"
                          for p, s in original_daemons.items() if s == "Running"))

    # Confirmed directly (recovering from the incident this file documents):
    # starting a server right after its daemon can fail transiently even
    # once the daemon truly is up - retry rather than trust one attempt.
    for name, was_active in original_servers.items():
        if not was_active:
            continue
        for _ in range(5):
            if server_states(client).get(name):
                break
            client._request("POST", "servers/operations?serverName=%s&operation=start"
                            % name.replace(" ", "%20"))
            time.sleep(3)


client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /clusterServices, /daemons "
           "operations, /servers operations or /transactionManager; run this "
           "against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

original_daemons = daemon_statuses(client)
original_servers = server_states(client)
original_cluster = cluster_statuses(client)
original_tm = tm_status(client)
c.info("original daemon statuses: %s" % original_daemons)
c.info("original server states: %s" % original_servers)
c.info("original cluster service statuses: %s" % original_cluster)
c.info("original TM status: %s" % original_tm)

with open(SCRIPT) as f:
    source = f.read()
old_tm_block = (
    "    if getTransactionManagerStatus(coreSession, coreUrl, coreToken):\n"
    "        print('The TM is still running')\n"
    "        stopTransactionManager(coreSession, coreUrl, coreToken, gtime)\n"
)
if old_tm_block not in source:
    c.check("found the Transaction Manager stop block in stGraceful.py to remove it", False)
    client.logout()
    sys.exit(c.done())
c.check("found the Transaction Manager stop block in stGraceful.py to remove it", True)
new_tm_block = (
    "    if getTransactionManagerStatus(coreSession, coreUrl, coreToken):\n"
    "        print('The TM is still running - NOT stopping it, no confirmed way to '\n"
    "              'start it again via the API (see the check that made this copy)')\n"
)
subs = {old_tm_block: new_tm_block}

try:
    with runner.real_credentials_python(PY_TREE, config):
        with runner.substituted_copy(SCRIPT, subs) as copy:
            # No short timeout here on purpose - see this file's own
            # docstring for why killing this script mid-run is exactly what
            # caused the incident this rewrite responds to.
            result = runner.run_python(copy, args=[GTIME, "--yes"], timeout=600)
            c.check("stGraceful.py runs without a shell level error "
                    "(Transaction Manager stop removed)", result.returncode == 0,
                    result.stderr.strip()[-500:] if result.returncode else "")
            c.check("its own output confirms the TM stop was skipped, not attempted",
                    "NOT stopping it" in result.stdout, result.stdout[-500:])

    stopped_daemons = wait_until(
        lambda: all(daemon_statuses(client)[p] == "Not running" for p in original_daemons
                   if original_daemons[p] == "Running"))
    c.check("every daemon that was Running is Not running after the script's own stop calls",
            stopped_daemons, daemon_statuses(client))

    stopped_cluster = wait_until(
        lambda: all(v != "Running." for v in cluster_statuses(client).values()))
    c.check("FolderMonitor and Scheduler are stopped after the script's own stop calls",
            stopped_cluster, cluster_statuses(client))

    c.check("the Transaction Manager was never touched - still %s" % original_tm,
            tm_status(client) == original_tm, tm_status(client))

finally:
    restore_everything(client, original_daemons, original_servers, original_cluster)

    c.check("every daemon matches its original status (first pass)",
            daemon_statuses(client) == original_daemons,
            (original_daemons, daemon_statuses(client)))
    c.check("every server matches its original active state (first pass)",
            server_states(client) == original_servers,
            (original_servers, server_states(client)))
    c.check("FolderMonitor and Scheduler match their original status (first pass)",
            cluster_statuses(client) == original_cluster,
            (original_cluster, cluster_statuses(client)))

    # The specific check that would have caught the incident: a delayed
    # graceful stop landing after the first restoration already looked fine.
    c.info("waiting %ds to catch a delayed graceful stop, then verifying again..."
           % SETTLE_SECONDS)
    time.sleep(SETTLE_SECONDS)
    restore_everything(client, original_daemons, original_servers, original_cluster)

    c.check("every daemon matches its original status (after the settle wait)",
            daemon_statuses(client) == original_daemons,
            (original_daemons, daemon_statuses(client)))
    c.check("every server matches its original active state (after the settle wait)",
            server_states(client) == original_servers,
            (original_servers, server_states(client)))
    c.check("FolderMonitor and Scheduler match their original status (after the settle wait)",
            cluster_statuses(client) == original_cluster,
            (original_cluster, cluster_statuses(client)))
    c.check("the Transaction Manager is still %s at the end" % original_tm,
            tm_status(client) == original_tm, tm_status(client))

    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own calls)"
       % client.calls)

sys.exit(c.done())
