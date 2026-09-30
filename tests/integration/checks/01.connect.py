#!/usr/bin/env python3
"""
Read only. Proves we can talk to the server at all, and that the session
protocol works: Referer, the CSRF handshake, and logout.

Run this first. If it fails, nothing else will work and the reason is here.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
from st_client import find_value  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

c = st_client.Checker("Connectivity and session (read only)")
c.info("server: https://%s:%s" % (config.get("st_server"), config.get("st_port")))

client = st_client.client_from_config(config)

# -- login ------------------------------------------------------------------
try:
    token = client.login()
except st_client.STError as e:
    c.check("login", False, e)
    sys.exit(c.done())

c.check("login to /myself succeeds", True)

if token:
    c.info("the server issued a csrfToken, so it is 20230525 or later")
    c.check("the token is sent on later calls",
            client.get("myself").status == 200)
else:
    c.info("no csrfToken issued, so this server predates the 20230525 release")

# -- who am I ---------------------------------------------------------------
# No example anywhere in this repository parses a field out of the admin
# /myself response, so which field carries the account name is not something
# this harness has actually confirmed on a real server. Rather than assert a
# field name that might be wrong, search for the configured user anywhere in
# the response and report the path if found. If it is not found anywhere,
# report the field NAMES that were returned (never values, so nothing
# sensitive is printed) rather than fail on an assumption.
response = client.get("myself")
c.check("GET /myself returns 200", response.status == 200, response.status)
me = response.json() or {}

match_path = find_value(me, config.get("st_user"))
if match_path:
    c.check("/myself identifies the account we logged in as", True)
    c.info("found at %s" % match_path)
elif isinstance(me, dict):
    c.info('could not find "%s" anywhere in the /myself response' % config.get("st_user"))
    c.info("its top level fields are: %s" % ", ".join(sorted(me.keys())) or "(none)")
else:
    c.info("/myself did not return a JSON object")

# -- version ----------------------------------------------------------------
response = client.get("version")
c.check("GET /version returns 200", response.status == 200, response.status)
version = (response.json() or {}).get("version")
if version:
    c.info("server version: %s" % version)

# -- the Referer header is genuinely required -------------------------------
# Send one call without it and confirm the server objects. If this passes on
# your server, the header really is load bearing and not decoration.
saved = client.referer
client.referer = ""
try:
    bare = client._request("GET", "version")
    if bare.status == 200:
        c.info("this server accepted a call with no Referer, "
               "which is looser than the documented behaviour")
    else:
        c.check("a call with no Referer is refused", bare.status in (400, 403),
                bare.status)
finally:
    client.referer = saved

# -- logout -----------------------------------------------------------------
client.logout()
c.check("logout succeeds", True)
c.info("%d API calls issued" % client.calls)

sys.exit(c.done())
