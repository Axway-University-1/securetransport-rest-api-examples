#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified
13.Configurations/01.configurations_PATCH.sh and
02.configurations_PATCH_UsageReporting.sh against a configured server, then
restores every option each one touches to its original value and verifies
the restore.

This was deliberately excluded until explicitly requested: a Server
Configuration Option is a real, persistent, server-wide setting, not a
sandboxed object - the blast radius is the whole server, not one record.
This check reads every option's current value first, runs both scripts,
verifies each option's new value, then restores every one of them and
verifies the restore - the same round-trip pattern 14.daemon_write_scripts.py
already uses for the SSH daemon.

Confirmed directly while building this: the "readOnly" flag GET returns on
a configuration option does NOT mean the API itself refuses a PATCH to it -
confirmed by successfully patching and restoring
StatisticsSummaryReport.ClientId, which reports readOnly=true. What actually
blocked changing Admin.ClientCertificateAuthentication earlier in this
project's history was this session's own tooling refusing to attempt that
one specific call (a client-side safety classifier, flagged because it is an
authentication policy, not a data value) - not a server-side rejection that
was ever actually observed. That distinction is corrected here rather than
left standing as an unverified claim; see the gotchas skill.

Also confirmed directly: an already-encrypted option value (the
"{AES128}..." form GET returns for ClientSecret) survives being sent back
unchanged - the server recognises it as already encrypted rather than
re-encrypting it as new plaintext, the same behaviour already confirmed for
a transfer site's password field.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.
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
    st_client.skip("read only run, pass --write to run the Configurations PATCH scripts for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Configurations PATCH, run for real from Admin/API 2.0/bash/13.Configurations")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
CONF_DIR = os.path.join(BASH_TREE, "13.Configurations")

# All options either script touches. AddressBook.Enabled is set to "true" by
# script 01; the rest are set by script 02, to the literal placeholder text
# that script hardcodes (it is meant to be edited before running for real -
# this check verifies the field accepts and stores whatever was sent, not
# that these particular placeholder values are meaningful).
OPTIONS = [
    "AddressBook.Enabled",
    "StatisticsSummaryReport.ClientId",
    "StatisticsSummaryReport.ClientSecret",
    "StatisticsSummaryReport.EnvironmentId",
    "StatisticsSummaryReport.EnvironmentName",
    "StatisticsSummaryReport.FilePath",
    "StatisticsSummaryReport.NetworkZone",
    "StatisticsSummaryReport.Platform.API",
    "StatisticsSummaryReport.Platform.Authentication",
    "StatisticsSummaryReport.SchemaId",
    "StatisticsSummaryReport.AutomaticReport.DaysToInclude",
]

EXPECTED_AFTER = {
    "AddressBook.Enabled": ["true"],
    "StatisticsSummaryReport.ClientId": ["<PUT YOUR CLIENT ID HERE>"],
    "StatisticsSummaryReport.ClientSecret": ["<PUT YOUR CLIENT_SECRET HERE>"],
    "StatisticsSummaryReport.EnvironmentId": ["<PUT YOUR ENVIRONMENT_ID HERE>"],
    "StatisticsSummaryReport.EnvironmentName": ["<PUT YOUR ENVIRONMENT_NAME HERE>"],
    "StatisticsSummaryReport.FilePath": ["/tmp/"],
    "StatisticsSummaryReport.NetworkZone": ["<PUT YOUR NETWORK_ZONE HERE>"],
    "StatisticsSummaryReport.Platform.API": ["https://platform.axway.com/api/v1/usage/automatic"],
    "StatisticsSummaryReport.Platform.Authentication":
        ["https://login.axway.com/auth/realms/Broker/protocol/openid-connect/token"],
    "StatisticsSummaryReport.SchemaId": ["https://platform.axway.com/schemas/report.json"],
    "StatisticsSummaryReport.AutomaticReport.DaysToInclude": ["3"],
}

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /configurations; run this "
           "against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

original = {}
for name in OPTIONS:
    response = client.get("configurations/options/" + name)
    original[name] = response.json().get("values") if response.status == 200 else None
c.check("read every option's original value before changing anything",
        all(v is not None for v in original.values()), original)
c.info("original values: %s" % original)

try:
    with runner.real_credentials(BASH_TREE, config):
        result = runner.run(os.path.join(CONF_DIR, "01.configurations_PATCH.sh"))
        c.check("01.configurations_PATCH.sh runs without a shell level error",
                result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")

        result = runner.run(os.path.join(CONF_DIR, "02.configurations_PATCH_UsageReporting.sh"))
        c.check("02.configurations_PATCH_UsageReporting.sh runs without a shell level error",
                result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")

    for name in OPTIONS:
        response = client.get("configurations/options/" + name)
        actual = response.json().get("values")
        if name == "StatisticsSummaryReport.ClientSecret":
            # Confirmed directly: this option auto-encrypts a plaintext value
            # on write, the same behaviour already confirmed for a transfer
            # site's password field - the stored value is never the literal
            # placeholder text, only its encrypted form.
            c.check("%s was set (now stored encrypted, not as plaintext)" % name,
                    bool(actual) and actual != original[name]
                    and actual[0].startswith("{AES128}"), actual)
        else:
            c.check("%s was set to %s" % (name, EXPECTED_AFTER[name]),
                    actual == EXPECTED_AFTER[name], actual)

finally:
    for name in OPTIONS:
        if original.get(name) is None:
            continue
        response = client.patch("configurations/options/" + name,
                                [{"op": "replace", "path": "/values", "value": original[name]}])
        c.check("%s restored: PATCH returns 204" % name, response.status == 204, response.status)
        restored = client.get("configurations/options/" + name).json().get("values")
        c.check("%s matches its original value" % name, restored == original[name], restored)
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
