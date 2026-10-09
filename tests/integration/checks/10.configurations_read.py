#!/usr/bin/env python3
"""
Read only, deliberately. Confirms the shape of a Server Configuration Option
response against a configured server, without running either of the PATCH
scripts in Admin/API 2.0/bash/13.Configurations.

Those two scripts are not exercised here on purpose: a Configuration Option is
not a disposable per-run object like an account or a server, it is one of the
server's own settings. 01.configurations_PATCH.sh flips
AddressBook.Enabled and 02...UsageReporting.sh points the server at the Axway
Platform for usage reporting - both change real, persistent, server wide
behaviour, not test data, so this check only reads.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

c = st_client.Checker("Configurations, read only")

client = harness.connect(config, c, mock=("the bundled mock does not implement /configurations; run this "
                                          "against a real server to exercise it"))

OPTION = "AddressBook.Enabled"
response = client.get("configurations/options/" + OPTION)
c.check("GET /configurations/options/%s returns 200" % OPTION, response.status == 200,
        response.status)

option = response.json() or {}
c.check("the option carries its own name back", option.get("name") == OPTION, option.get("name"))
c.check("the option has a values list, which is what a PATCH would replace",
        isinstance(option.get("values"), list), option.get("values"))
c.info("current value: %s" % option.get("values"))

c.check("HEAD on the same option agrees it exists",
        client.head("configurations/options/" + OPTION).status == 200)

missing = "ZZTEST_not_a_real_option"
c.check("GET of a made up option returns 404",
        client.get("configurations/options/" + missing).status == 404)

client.logout()

sys.exit(c.done())
