#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified
Admin/API 2.0/bash/02.Introduction/04.myself_PATCH.sh against a throwaway
administrator this check creates and deletes - never against the admin
account the rest of this suite authenticates as.

That script replaces whichever account is currently authenticated's own
password with the one in the environment variable ST_NEW_PASSWORD. Running it
against the configured st_user would lock every other check out of that
account, on this and every future run - which is exactly why
12.myself_and_version_scripts.py excludes it. The script itself is not
parameterised by account name - it just acts on whoever ST_USER/ST_PASSWORD
authenticate as - so pointing it at a disposable administrator instead needs
no substituted copy: the real file runs completely unmodified.

It used to send the literal text TYPE_WHATEVER_YOU_WANT_HERE when run with no
argument, which changed the password every other example logs in as. It now
sends nothing without ST_NEW_PASSWORD (exit 2), and this check proves that
first: the throwaway administrator still logs in with its old password after a
bare run, and after one with an empty ST_NEW_PASSWORD.

Objects touched: a throwaway administrator, ZZTEST_myself_patch_admin,
created and deleted by this check itself, never the folder's own scripts
(there are none - 02.Introduction has no administrator lifecycle example).

Two things confirmed directly, neither demonstrated anywhere else in this
repository:

  - /accounts and /administrators are different resources. POST /accounts
    with type="administrator" is rejected with "Invalid discriminator
    value" - administrators live under their own /administrators endpoint,
    with a roleName-based rights model, not the type=user/service/template
    one /accounts uses.
  - An administrator created through POST /administrators defaults to
    localAuthentication=false, and Basic-auth login against it then fails
    with 401. localAuthentication=true must be set explicitly on creation
    for password login to work at all. Every other example in this
    repository authenticates as an account that already has this set on the
    server ahead of time, so nothing else here demonstrates it. (It also needs
    `parent`, the administrator it is created under.)

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.
"""
import contextlib
import os
import secrets
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the myself PATCH script for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("myself PATCH, run for real against a throwaway administrator")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
INTRO_DIR = os.path.join(BASH_TREE, "02.Introduction")
SCRIPT = os.path.join(INTRO_DIR, "04.myself_PATCH.sh")
NAME = "ZZTEST_myself_patch_admin"
OLD_PASSWORD = "Zz1!Throwaway"
# A password of this check's own: with a space, a quote and a dollar sign, to prove the body
# the script builds with jq is valid JSON whatever is in the password
NEW_PASSWORD = 'Zz2 "q" $x ' + secrets.token_hex(4)

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /administrators; run this "
           "against a real server to exercise it")
    client.logout()
    sys.exit(c.done())


@contextlib.contextmanager
def new_password(value):
    """ST_NEW_PASSWORD in the environment of the script (None: not set at all), put back afterwards."""
    previous = os.environ.get("ST_NEW_PASSWORD")
    if value is None:
        os.environ.pop("ST_NEW_PASSWORD", None)
    else:
        os.environ["ST_NEW_PASSWORD"] = value
    try:
        yield
    finally:
        if previous is None:
            os.environ.pop("ST_NEW_PASSWORD", None)
        else:
            os.environ["ST_NEW_PASSWORD"] = previous


def logs_in(password):
    probe = st_client.client_from_config(dict(config, st_user=NAME, st_password=password))
    try:
        probe.login()
        probe.logout()
        return True
    except st_client.STError:
        return False


created = False

try:
    if client.exists("administrators/" + NAME):
        c.info('an administrator named "%s" already exists on this server; '
               "skipping rather than risk touching it" % NAME)
    else:
        response = client.post("administrators", {
            "loginName": NAME,
            "roleName": "Master Administrator",
            "parent": config["st_user"],
            "localAuthentication": True,
            "passwordCredentials": {"password": OLD_PASSWORD},
        })
        created = response.status == 201
        c.check("created a throwaway administrator for this script", created,
                response.text[:200])

        if created:
            throwaway = dict(config, st_user=NAME, st_password=OLD_PASSWORD)
            c.check("the throwaway administrator logs in with its password", logs_in(OLD_PASSWORD))

            with runner.real_credentials(BASH_TREE, throwaway):
                # -- bare: nothing is sent --------------------------------------------
                with new_password(None):
                    result = runner.run(SCRIPT)
                c.check("04.myself_PATCH.sh with no ST_NEW_PASSWORD exits 2", result.returncode == 2,
                        (result.returncode, result.stdout.strip()[-200:]))
                c.check("and says what to set", "set ST_NEW_PASSWORD" in result.stdout, result.stdout[-200:])
                with new_password(""):
                    result = runner.run(SCRIPT)
                c.check("with an empty ST_NEW_PASSWORD it exits 2 too", result.returncode == 2, result.returncode)
            c.check("the old password still works after the two bare runs", logs_in(OLD_PASSWORD))
            c.check("and the placeholder it used to send does not", not logs_in("TYPE_WHATEVER_YOU_WANT_HERE"))

            # -- a refusal: the current password is wrong, so the server answers 401 and exit is 1 ----
            wrong = dict(throwaway, st_password="Not.The.Password")
            with runner.real_credentials(BASH_TREE, wrong), new_password(NEW_PASSWORD):
                result = runner.run(SCRIPT)
            c.check("with a wrong current password it exits 1 and shows HTTP 401",
                    result.returncode == 1 and "HTTP 401" in result.stdout, (result.returncode, result.stdout[-200:]))
            c.check("and the password was not changed", logs_in(OLD_PASSWORD) and not logs_in(NEW_PASSWORD))

            # -- the change ------------------------------------------------------------------
            with runner.real_credentials(BASH_TREE, throwaway), new_password(NEW_PASSWORD):
                result = runner.run(SCRIPT)
            c.check("04.myself_PATCH.sh with ST_NEW_PASSWORD runs, prints HTTP 204 and exits 0",
                    result.returncode == 0 and "HTTP 204" in result.stdout,
                    (result.returncode, result.stdout[-200:], result.stderr.strip()[-300:]))
            c.check("it never prints the password", NEW_PASSWORD not in result.stdout + result.stderr)
            c.check("the old password no longer works after the PATCH", not logs_in(OLD_PASSWORD))
            c.check("the new password from the environment now works (it holds a space, quotes and a dollar sign)",
                    logs_in(NEW_PASSWORD))

            # -- a second run, as the script says to put it back: logging in with the new one ---
            now = dict(throwaway, st_password=NEW_PASSWORD)
            with runner.real_credentials(BASH_TREE, now), new_password(OLD_PASSWORD):
                result = runner.run(SCRIPT)
            c.check("run again with the old password, logging in with the new one, it puts the password back",
                    result.returncode == 0 and logs_in(OLD_PASSWORD) and not logs_in(NEW_PASSWORD), result.stdout[-200:])

finally:
    if created:
        client.delete("administrators/" + NAME)
        c.check('the throwaway administrator "%s" was removed' % NAME,
                not client.exists("administrators/" + NAME))
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own curl calls)"
       % client.calls)

sys.exit(c.done())
