#!/usr/bin/env python3
"""
Read only. Runs the real, unmodified daemon and server list scripts in
Admin/API 2.0/bash/03.Connect against a configured server, plus the one
script that reads a single daemon's own settings without changing them.

Deliberately does not touch 05 or 13: those start and stop real daemons and
servers outright, which can interrupt live file transfers on anything but a
fully disposable lab - not something to do automatically. See
14.daemon_write_scripts.py for the write half of 03/04 this folder gets
instead - deliberately a separate, explicitly-requested check, since unlike
05/13 (skipped outright) or 06.servers_scripts.py's own throwaway server,
03/04 change the one live SSH daemon this endpoint will ever address, and
that check restores it afterward rather than avoiding it.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

c = st_client.Checker("Connect, read only, from Admin/API 2.0/bash/03.Connect")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
CONNECT_DIR = os.path.join(BASH_TREE, "03.Connect")

client = harness.connect(config, c, mock=("the bundled mock does not implement /daemons or /servers; run "
                                          "this against a real server to exercise it"))

with runner.real_credentials(BASH_TREE, config):
    result = runner.run(os.path.join(CONNECT_DIR, "01.daemons_GET.sh"))
    c.check("01.daemons_GET.sh runs without a shell level error", result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")

    result = runner.run(os.path.join(CONNECT_DIR, "02.daemons_name_GET.sh"))
    c.check("02.daemons_name_GET.sh runs without a shell level error", result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")
    ssh = client.get("daemons/ssh").json() or {}
    real_banner = ssh.get("banner")
    if real_banner:
        c.check("the script's own output reports the real banner is defined",
                "There is a banner defined" in result.stdout, result.stdout[-300:])
    else:
        c.check("the script's own output reports no real banner is defined",
                "There is no banner defined" in result.stdout, result.stdout[-300:])
    c.check("the script's own simulated fake banner check reports one is defined",
            "This is a SecureTransport REST API test banner." in result.stdout,
            result.stdout[-300:])

    result = runner.run(os.path.join(CONNECT_DIR, "06.servers_GET.sh"))
    c.check("06.servers_GET.sh runs without a shell level error", result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")

daemons = client.get("daemons").json() or {}
statuses = {k: v for k, v in daemons.items() if k.endswith("Status")}
c.check("GET /daemons returns at least one *Status field", bool(statuses), daemons)
c.check("every status is one of the two documented values",
        all(v in ("Running", "Not running") for v in statuses.values()), statuses)
for name, status in statuses.items():
    c.info("%s: %s" % (name, status))

servers = list(client.page("servers", page_size=200))
c.info("%d server(s) configured on this server" % len(servers))

client.logout()

sys.exit(c.done())
