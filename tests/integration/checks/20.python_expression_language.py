#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified python3 Expression
Language exercises in Admin/API 2.0/python/python3/14.ExpressionLanguage
against a configured server, and independently verifies what each one
claims about the field it demonstrates.

This is the python counterpart to 19.bash_expression_language.py - the same
eight worked examples, run through the real scripts in that folder instead.
Every script there is self-contained the same way: it creates one or more
throwaway ZZTEST_EL_-prefixed objects, shows the field it demonstrates, and
deletes what it created before exiting. This check runs each for real and
checks:

  - the script's own printed GET response shows the exact expression text
    this check independently expects
  - after every script has run, nothing named ZZTEST_EL_* is left behind in
    routes, sites or loginRestrictionPolicies

Needs tests/local/pyvenv - see 15.python_read_scripts.py's docstring for how
to create it.

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
    st_client.skip("read only run, pass --write to run the Expression Language scripts for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

c = st_client.Checker("Expression Language, run for real from "
                       "Admin/API 2.0/python/python3/14.ExpressionLanguage")

PY_TREE = runner.path("Admin", "API 2.0", "python")
EL_DIR = os.path.join(PY_TREE, "python3", "14.ExpressionLanguage")


def script(name):
    return os.path.join(EL_DIR, name)


def run_and_check(name, expected_snippets):
    result = runner.run_python(script(name), timeout=60)
    c.check("%s runs without a shell level error" % name, result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")
    for snippet in expected_snippets:
        c.check("%s's own output shows: %s" % (name, snippet), snippet in result.stdout,
                result.stdout[-500:])


client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /routes, /sites or "
           "/loginRestrictionPolicies; run this against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

with runner.real_credentials_python(PY_TREE, config):

    run_and_check("01.loginRestrictionPolicy_sessionExpression.py", [
        '"expression" : "${currentSessions <= 3}"',
    ])

    run_and_check("02.routes_condition_EL.py", [
        '"condition" : "${account.disabled != \'0\'}"',
        '"condition" : "${!empty account.email}"',
        '"condition" : "${transfer.transferredBytes ge 20}"',
    ])

    run_and_check("03.routes_step_fileFilterExpression_glob.py", [
        '"fileFilterExpression" : "*.xml"',
        '"fileFilterExpression" : "foo.??"',
        '"fileFilterExpression" : "*.[0-9]"',
        '"fileFilterExpression" : "*.[!0-9]"',
    ])

    run_and_check("04.routes_step_fileFilterExpression_regexp.py", [
        '"fileFilterExpression" : ".*\\\\.(xml|txt)"',
        '"fileFilterExpression" : "(?i)data\\\\.xml"',
        '"fileFilterExpression" : "^(?!.*__TID\\\\d{6}__[A-Za-z0-9]{16}).*$"',
    ])

    run_and_check("05.routes_step_condition_matches_backslashDoubling.py", [
        '"condition" : "${transfer.target.matches(\'.*\\\\\\\\.txt\')}"',
        '"condition" : "${transfer.target.matches(\'.*\\\\.txt\')}"',
    ])

    run_and_check("06.routes_step_renameExpression.py", [
        "${basename(transfer.target)}-${date('yyyyMMdd_HHmmss')}${extension(transfer.target)}",
        "${basename(transfer.target)}-${random()}.${extension(transfer.target)}",
        "${account.name}_${basename(transfer.target)}",
    ])

    run_and_check("07.transferSites_downloadPattern.py", [
        '"downloadPattern" : "*.xml"',
        '"downloadPattern" : "*.[0-9]"',
        '"downloadPattern" : ".*\\\\.(xml|txt)"',
        '"downloadPatternType" : "glob"',
        '"downloadPatternType" : "regex"',
    ])

    run_and_check("08.transferSites_dynamicProperties.py", [
        '"host" : "${DXAGENT_TRANSFERSAPI_SERVER}"',
        '"downloadPattern" : "${DXAGENT_TRANSFERSAPI_FILE}"',
    ])

leftovers = []
for collection in ("routes", "sites", "loginRestrictionPolicies"):
    for item in client.page(collection):
        if (item.get("name") or "").startswith("ZZTEST_EL_"):
            leftovers.append("%s/%s" % (collection, item.get("name")))
c.check("no ZZTEST_EL_ object is left behind in routes, sites or loginRestrictionPolicies",
        not leftovers, leftovers)

client.logout()
c.info("%d API calls issued by the verification client (not counting the scripts' own calls)"
       % client.calls)

sys.exit(c.done())
