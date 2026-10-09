#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified bash Expression Language
exercises in Admin/API 2.0/bash/14.ExpressionLanguage against a configured
server, and independently verifies what each one claims about the field it
demonstrates.

Every script in that folder is self-contained: it creates one or more
throwaway ZZTEST_EL_-prefixed objects (routes, a site, a login restriction
policy), shows the field it is demonstrating, and deletes what it created
before exiting. This check does not need to create or clean up anything
itself - it runs each script for real and checks two things:

  - the script's own GET, printed to stdout, shows the exact expression text
    this check independently expects, proving the escaping in that script's
    curl -d payload produced the right bytes on the wire
  - after every script has run, nothing named ZZTEST_EL_* is left behind in
    routes, sites or loginRestrictionPolicies - proving each script's own
    cleanup actually worked, not just that it was attempted

What each stored expression actually evaluates to at transfer time is not
tested here - that needs a live transfer with real files, a different kind
of test than this repository's integration checks run. This proves the
fields accept and store the expressions exactly as each script intends, and
that the two independent escaping rules covered in 04 and 05 (a raw JSON
backslash, and an EL string literal's own backslash-doubling) are both
correctly applied in the shipped scripts.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.
"""
import os
import sys
from urllib.parse import quote

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the Expression Language scripts for real")

c = st_client.Checker("Expression Language, run for real from "
                       "Admin/API 2.0/bash/14.ExpressionLanguage")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
EL_DIR = os.path.join(BASH_TREE, "14.ExpressionLanguage")


def script(name):
    return os.path.join(EL_DIR, name)


def run_and_check(name, expected_snippets):
    result = runner.run(script(name), timeout=60)
    c.check("%s runs without a shell level error" % name, result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")
    for snippet in expected_snippets:
        c.check("%s's own output shows: %s" % (name, snippet), snippet in result.stdout,
                result.stdout[-500:])


client = harness.connect(config, c, mock=("the bundled mock does not implement /routes, /sites or "
                                          "/loginRestrictionPolicies; run this against a real server to exercise it"))


def left_behind():
    """(path, name) of every ZZTEST_EL_ object, the name these examples give what they make, in routes, sites and policies."""
    found = []
    for collection in ("routes", "sites", "loginRestrictionPolicies"):
        for item in client.page(collection):
            name = item.get("name") or ""
            if name.startswith("ZZTEST_EL_"):
                key = name if collection == "loginRestrictionPolicies" else item.get("id")
                found.append(("%s/%s" % (collection, quote(str(key), safe="")), "%s/%s" % (collection, name)))
    return found


try:
    with runner.real_credentials(BASH_TREE, config):

        run_and_check("01.loginRestrictionPolicy_sessionExpression.sh", [
            '"expression" : "${currentSessions <= 3}"',
        ])

        run_and_check("02.routes_condition_EL.sh", [
            '"condition" : "${account.disabled != \'0\'}"',
            '"condition" : "${!empty account.email}"',
            '"condition" : "${transfer.transferredBytes ge 20}"',
        ])

        run_and_check("03.routes_step_fileFilterExpression_glob.sh", [
            '"fileFilterExpression" : "*.xml"',
            '"fileFilterExpression" : "foo.??"',
            '"fileFilterExpression" : "*.[0-9]"',
            '"fileFilterExpression" : "*.[!0-9]"',
        ])

        run_and_check("04.routes_step_fileFilterExpression_regexp.sh", [
            '"fileFilterExpression" : ".*\\\\.(xml|txt)"',
            '"fileFilterExpression" : "(?i)data\\\\.xml"',
            '"fileFilterExpression" : "^(?!.*__TID\\\\d{6}__[A-Za-z0-9]{16}).*$"',
        ])

        run_and_check("05.routes_step_condition_matches_backslashDoubling.sh", [
            '"condition" : "${transfer.target.matches(\'.*\\\\\\\\.txt\')}"',
            '"condition" : "${transfer.target.matches(\'.*\\\\.txt\')}"',
        ])

        run_and_check("06.routes_step_renameExpression.sh", [
            "${basename(transfer.target)}-${date('yyyyMMdd_HHmmss')}${extension(transfer.target)}",
            "${basename(transfer.target)}-${random()}.${extension(transfer.target)}",
            "${account.name}_${basename(transfer.target)}",
        ])

        run_and_check("07.transferSites_downloadPattern.sh", [
            '"downloadPattern" : "*.xml"',
            '"downloadPattern" : "*.[0-9]"',
            '"downloadPattern" : ".*\\\\.(xml|txt)"',
            '"downloadPatternType" : "glob"',
            '"downloadPatternType" : "regex"',
        ])

        run_and_check("08.transferSites_dynamicProperties.sh", [
            '"host" : "${DXAGENT_TRANSFERSAPI_SERVER}"',
            '"downloadPattern" : "${DXAGENT_TRANSFERSAPI_FILE}"',
        ])
finally:
    leftovers = [label for _, label in left_behind()]
    c.check("no ZZTEST_EL_ object is left behind in routes, sites or loginRestrictionPolicies",
            not leftovers, leftovers)
    # what a script that failed half way left behind is removed: these are the names of these examples only
    for path, _ in left_behind():
        client.delete(path)
    client.logout()
c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
