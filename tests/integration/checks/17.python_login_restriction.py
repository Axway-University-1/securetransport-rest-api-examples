#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified
stAddLoginRestrictionRule.py in Admin/API 2.0/python/python3 against a
throwaway login restriction policy this check creates and deletes.

The script takes the policy name as a real command line argument
(sys.argv[1]) rather than hardcoding one, so no substitution is needed at
all - pointing it at a throwaway policy is exactly how the script is meant
to be used. The rule it adds ("sessions fewer than 4") is hardcoded, but a
brand new policy has no rules to collide with.

/loginRestrictionPolicies is a real, separate resource - confirmed directly:
POST requires a "type" (ALLOW_THEN_DENY or DENY_THEN_ALLOW), and a policy
starts with an empty rules array and isDefault=false, isolated from every
other policy until something (a business unit, a site) is actually
configured to use it - which this check never does, so the throwaway policy
has no effect on any real login while it exists.

Needs tests/local/pyvenv - see 15.python_read_scripts.py's docstring.

Leaves a log file, updateLoginRestrictions.log, next to itself; this check
removes it afterward.

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
    st_client.skip("read only run, pass --write to run the login restriction script for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

c = st_client.Checker("Python login restriction rule, run for real from "
                       "Admin/API 2.0/python/python3")

PY_TREE = runner.path("Admin", "API 2.0", "python")
PY_DIR = os.path.join(PY_TREE, "python3")
NAME = "ZZTEST_login_policy"

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /loginRestrictionPolicies; "
           "run this against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

created = False

try:
    if client.exists("loginRestrictionPolicies/" + NAME):
        c.info('a login restriction policy named "%s" already exists on '
               "this server; skipping this check rather than touch it" % NAME)
    else:
        response = client.post("loginRestrictionPolicies",
                               {"name": NAME, "type": "ALLOW_THEN_DENY"})
        created = response.status == 201
        c.check("created a throwaway login restriction policy", created,
                response.text[:200])

        if created:
            with runner.real_credentials_python(PY_TREE, config):
                result = runner.run_python(
                    os.path.join(PY_DIR, "stAddLoginRestrictionRule.py"), [NAME])
                c.check("stAddLoginRestrictionRule.py runs without a shell level error",
                        result.returncode == 0,
                        result.stderr.strip()[-300:] if result.returncode else "")

            policy = client.get("loginRestrictionPolicies/" + NAME).json() or {}
            rules = policy.get("rules") or []
            c.check("the new rule is present on the policy",
                    any(r.get("name") == "sessions fewer than 4" for r in rules), rules)
            rule = next((r for r in rules if r.get("name") == "sessions fewer than 4"), {})
            c.check("the rule's expression matches the script's payload",
                    rule.get("expression") == "${currentSessions <= 3}", rule)

finally:
    if created:
        client.delete("loginRestrictionPolicies/" + NAME)
        c.check("the throwaway login restriction policy was removed",
                not client.exists("loginRestrictionPolicies/" + NAME))
    logfile = os.path.join(PY_DIR, "updateLoginRestrictions.log")
    if os.path.exists(logfile):
        os.remove(logfile)
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own calls)"
       % client.calls)

sys.exit(c.done())
