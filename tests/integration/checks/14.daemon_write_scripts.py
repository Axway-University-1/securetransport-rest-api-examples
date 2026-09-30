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
the live SSH daemon. 03.daemons_name_PUT.sh's second call (a negative
maxConnections) is expected to be rejected and not take effect;
04.daemons_name_PATCH.sh's three PATCH calls change maxConnections,
preferBouncyCastleProvider and banner again. New SSH connections during the
run are subject to whatever maxConnections is set to at that moment; no call
here drops already-established connections.

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
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the daemon PUT/PATCH scripts for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Daemon PUT/PATCH, run for real against the live SSH daemon, then restored")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
CONNECT_DIR = os.path.join(BASH_TREE, "03.Connect")

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /daemons; run this against a "
           "real server to exercise it")
    client.logout()
    sys.exit(c.done())

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

try:
    with runner.real_credentials(BASH_TREE, config):
        result = runner.run(os.path.join(CONNECT_DIR, "03.daemons_name_PUT.sh"))
        c.check("03.daemons_name_PUT.sh runs without a shell level error",
                result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")

    after_put = client.get("daemons/ssh").json() or {}
    c.check("the valid PUT (maxConnections=10) took effect",
            after_put.get("maxConnections") == 10, after_put)
    c.check("the valid PUT's preferBouncyCastleProvider=false took effect",
            after_put.get("preferBouncyCastleProvider") is False, after_put)
    c.check("the valid PUT's banner took effect",
            after_put.get("banner") == "This is a SecureTransport REST API test banner.",
            after_put)
    c.check("the invalid PUT (maxConnections=-10) was rejected, not applied",
            after_put.get("maxConnections") != -10, after_put)

    with runner.real_credentials(BASH_TREE, config):
        result = runner.run(os.path.join(CONNECT_DIR, "04.daemons_name_PATCH.sh"))
        c.check("04.daemons_name_PATCH.sh runs without a shell level error",
                result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")

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
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
