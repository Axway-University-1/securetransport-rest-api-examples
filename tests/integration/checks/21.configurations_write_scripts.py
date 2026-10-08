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

Both scripts used to change the whole server when run with no arguments (01 set
AddressBook.Enabled to true, 02 wrote the placeholder text <PUT YOUR CLIENT_SECRET HERE>
and nine others into the usage reporting options). They now send nothing without
their input: 01 needs the new value, 02 needs ten environment variables (ST_USAGE_*)
and refuses a missing or placeholder one, both with exit 2. This check proves that
first (bare runs leave every option as it was), then runs 01 with the value the option
already has (a no-op, so the address book is never switched) and with a harmless change
to the number of days of the report, and 02 with test values of its own, and reads the
old values the scripts print against what it read itself.

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
a transfer site's password field. A plain value is stored encrypted, and the
encrypted text is different on every write.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.
"""
import contextlib
import json
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

# All options either script touches. AddressBook.Enabled is given the value it has, by script 01;
# the rest are set by script 02, to the values of its ST_USAGE_* variables.
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
DAYS = "StatisticsSummaryReport.AutomaticReport.DaysToInclude"

# The values 02 is given: this check's own, not the lab's. Platform.API and .Authentication differ from the
# real addresses on purpose, so that the change is seen; they are put back at the end like everything else.
USAGE_ENV = {
    "ST_USAGE_CLIENT_ID": "ZZTEST-client-id",
    "ST_USAGE_CLIENT_SECRET": 'ZZTEST secret with a "quote" and $dollar',
    "ST_USAGE_ENVIRONMENT_ID": "ZZTEST-environment-id",
    "ST_USAGE_ENVIRONMENT_NAME": "ZZTEST environment",
    "ST_USAGE_FILE_PATH": "/tmp/zztest_usage_reports",
    "ST_USAGE_NETWORK_ZONE": "ZZTEST-zone",
    "ST_USAGE_PLATFORM_API": "https://platform.example.com/api/v1/usage/automatic",
    "ST_USAGE_PLATFORM_AUTHENTICATION": "https://login.example.com/auth/token",
    "ST_USAGE_SCHEMA_ID": "https://platform.example.com/schemas/report.json",
    "ST_USAGE_DAYS_TO_INCLUDE": "5",
}
EXPECTED_AFTER = {
    "StatisticsSummaryReport.ClientId": [USAGE_ENV["ST_USAGE_CLIENT_ID"]],
    "StatisticsSummaryReport.EnvironmentId": [USAGE_ENV["ST_USAGE_ENVIRONMENT_ID"]],
    "StatisticsSummaryReport.EnvironmentName": [USAGE_ENV["ST_USAGE_ENVIRONMENT_NAME"]],
    "StatisticsSummaryReport.FilePath": [USAGE_ENV["ST_USAGE_FILE_PATH"]],
    "StatisticsSummaryReport.NetworkZone": [USAGE_ENV["ST_USAGE_NETWORK_ZONE"]],
    "StatisticsSummaryReport.Platform.API": [USAGE_ENV["ST_USAGE_PLATFORM_API"]],
    "StatisticsSummaryReport.Platform.Authentication": [USAGE_ENV["ST_USAGE_PLATFORM_AUTHENTICATION"]],
    "StatisticsSummaryReport.SchemaId": [USAGE_ENV["ST_USAGE_SCHEMA_ID"]],
    DAYS: [USAGE_ENV["ST_USAGE_DAYS_TO_INCLUDE"]],
}


@contextlib.contextmanager
def environment(values):
    """Put exactly these ST_USAGE_* variables in the environment of the scripts (a None value is not set), and put the rest back."""
    previous = {k: os.environ.get(k) for k in USAGE_ENV}
    for k in USAGE_ENV:
        os.environ.pop(k, None)
    os.environ.update({k: v for k, v in values.items() if v is not None})
    try:
        yield
    finally:
        for k, v in previous.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /configurations; run this "
           "against a real server to exercise it")
    client.logout()
    sys.exit(c.done())


def current():
    return {name: client.get("configurations/options/" + name).json().get("values") for name in OPTIONS}


original = {}
for name in OPTIONS:
    response = client.get("configurations/options/" + name)
    original[name] = response.json().get("values") if response.status == 200 else None
c.check("read every option's original value before changing anything",
        all(v is not None for v in original.values()), original)
c.info("original values: %s" % original)

try:
    with runner.real_credentials(BASH_TREE, config):
        # -- run bare: nothing is sent -----------------------------------------------------
        result = runner.run(os.path.join(CONF_DIR, "01.configurations_PATCH.sh"))
        c.check("01.configurations_PATCH.sh with no value exits 2", result.returncode == 2,
                (result.returncode, result.stdout[-200:]))
        with environment({}):
            result = runner.run(os.path.join(CONF_DIR, "02.configurations_PATCH_UsageReporting.sh"))
        c.check("02.configurations_PATCH_UsageReporting.sh with no variables exits 2 and names what is missing",
                result.returncode == 2 and result.stdout.count("is not set") == 9, (result.returncode, result.stdout[-300:]))
        with environment(dict(USAGE_ENV, ST_USAGE_CLIENT_SECRET="<PUT YOUR CLIENT_SECRET HERE>")):
            result = runner.run(os.path.join(CONF_DIR, "02.configurations_PATCH_UsageReporting.sh"))
        c.check("02 with a placeholder secret exits 2 and says so",
                result.returncode == 2 and "ST_USAGE_CLIENT_SECRET still holds a placeholder" in result.stdout,
                (result.returncode, result.stdout[-300:]))
        c.check("and every option is as it was after the three bare runs", current() == original, current())

        # -- 01: the value the option has already (a no-op), and a harmless change ---------------
        was = (original["AddressBook.Enabled"] or [""])[0]
        if was in ("true", "false"):
            result = runner.run(os.path.join(CONF_DIR, "01.configurations_PATCH.sh"), [was])
            c.check("01.configurations_PATCH.sh %s (what AddressBook.Enabled has) exits 0, prints HTTP 204 and the old values" % was,
                    result.returncode == 0 and "HTTP 204" in result.stdout
                    and "The values of AddressBook.Enabled are now: %s" % json.dumps(original["AddressBook.Enabled"]) in result.stdout,
                    (result.returncode, result.stdout[-300:], result.stderr.strip()[-300:]))
        else:
            c.info("AddressBook.Enabled holds %r, not true or false: 01 is not run on it" % original["AddressBook.Enabled"])
        result = runner.run(os.path.join(CONF_DIR, "01.configurations_PATCH.sh"), ["maybe"])
        c.check("01 with a value that is not true or false for AddressBook.Enabled exits 2", result.returncode == 2, result.returncode)
        result = runner.run(os.path.join(CONF_DIR, "01.configurations_PATCH.sh"), ["4", DAYS])
        c.check("01.configurations_PATCH.sh 4 <the days option> exits 0 and prints HTTP 204",
                result.returncode == 0 and "HTTP 204" in result.stdout, (result.returncode, result.stdout[-300:]))
        c.check("and it prints the command that puts the old value back",
                "To put the first one back: ./01.configurations_PATCH.sh %s %s" % (original[DAYS][0], DAYS) in result.stdout,
                result.stdout[-300:])
        c.check("the days option is now 4", client.get("configurations/options/" + DAYS).json().get("values") == ["4"])
        result = runner.run(os.path.join(CONF_DIR, "01.configurations_PATCH.sh"), ["4", "No.Such.Option"])
        c.check("01 on an option that does not exist exits 1 and says so",
                result.returncode == 1 and "Could not read the option No.Such.Option: HTTP 404" in result.stdout,
                (result.returncode, result.stdout[-300:]))

        # -- 02: with values of its own ----------------------------------------------------------
        with environment(USAGE_ENV):
            result = runner.run(os.path.join(CONF_DIR, "02.configurations_PATCH_UsageReporting.sh"))
        c.check("02.configurations_PATCH_UsageReporting.sh with its ten variables exits 0, ten times HTTP 204",
                result.returncode == 0 and result.stdout.count("HTTP 204") == 10,
                (result.returncode, result.stdout[-300:], result.stderr.strip()[-300:]))
        # the old values it printed are what the days option held after 01 (4) and what the others held at the start
        printed_before = dict(original, **{DAYS: ["4"]})
        c.check("02 printed the old values it read, as the server had them",
                all("  %s: %s" % (name, json.dumps(printed_before[name], separators=(",", ":"))) in result.stdout
                    for name in OPTIONS[1:]), result.stdout[:900])
        c.check("02 never printed the secret", USAGE_ENV["ST_USAGE_CLIENT_SECRET"] not in result.stdout + result.stderr)

    for name in OPTIONS:
        actual = client.get("configurations/options/" + name).json().get("values")
        if name == "StatisticsSummaryReport.ClientSecret":
            # Confirmed directly: this option auto-encrypts a plaintext value
            # on write, the same behaviour already confirmed for a transfer
            # site's password field - the stored value is never the literal
            # text sent, only its encrypted form.
            c.check("%s was set (now stored encrypted, not as plaintext)" % name,
                    bool(actual) and actual != original[name]
                    and actual[0].startswith("{AES128}"), actual)
        elif name == "AddressBook.Enabled":
            c.check("%s is what it was" % name, actual == original[name], actual)
        else:
            c.check("%s was set to %s" % (name, EXPECTED_AFTER[name]),
                    actual == EXPECTED_AFTER[name], actual)

    # -- 02 again, with no network zone: the option is set to empty ----------------------------
    with runner.real_credentials(BASH_TREE, config):
        with environment(dict(USAGE_ENV, ST_USAGE_NETWORK_ZONE=None)):
            result = runner.run(os.path.join(CONF_DIR, "02.configurations_PATCH_UsageReporting.sh"))
    c.check("02 with no ST_USAGE_NETWORK_ZONE exits 0 and sets the zone to empty",
            result.returncode == 0
            and client.get("configurations/options/StatisticsSummaryReport.NetworkZone").json().get("values") == [""],
            (result.returncode, result.stdout[-200:]))

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
