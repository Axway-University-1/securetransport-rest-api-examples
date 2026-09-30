#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified
Admin/API 2.0/bash/02.Introduction/04.myself_PATCH.sh against a throwaway
administrator this check creates and deletes - never against the admin
account the rest of this suite authenticates as.

That script replaces whichever account is currently authenticated's own
password with the literal string "TYPE_WHATEVER_YOU_WANT_HERE". Running it
against the configured st_user would lock every other check out of that
account, on this and every future run - which is exactly why
12.myself_and_version_scripts.py excludes it. The script itself is not
parameterised by account name - it just acts on whoever ST_USER/ST_PASSWORD
authenticate as - so pointing it at a disposable administrator instead needs
no substituted copy: the real file runs completely unmodified.

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
    server ahead of time, so nothing else here demonstrates it.

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
    st_client.skip("read only run, pass --write to run the myself PATCH script for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("myself PATCH, run for real against a throwaway administrator")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
INTRO_DIR = os.path.join(BASH_TREE, "02.Introduction")
NAME = "ZZTEST_myself_patch_admin"
OLD_PASSWORD = "Zz1!Throwaway"
# The literal value 04.myself_PATCH.sh hardcodes - this check does not choose it.
NEW_PASSWORD = "TYPE_WHATEVER_YOU_WANT_HERE"

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /administrators; run this "
           "against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

created = False

try:
    if client.exists("administrators/" + NAME):
        c.info('an administrator named "%s" already exists on this server; '
               "skipping rather than risk touching it" % NAME)
    else:
        response = client.post("administrators", {
            "loginName": NAME,
            "roleName": "Master Administrator",
            "localAuthentication": True,
            "passwordCredentials": {"password": OLD_PASSWORD},
        })
        created = response.status == 201
        c.check("created a throwaway administrator for this script", created,
                response.text[:200])

        if created:
            throwaway = dict(config)
            throwaway["st_user"] = NAME
            throwaway["st_password"] = OLD_PASSWORD

            with runner.real_credentials(BASH_TREE, throwaway):
                result = runner.run(os.path.join(INTRO_DIR, "04.myself_PATCH.sh"))
                c.check("04.myself_PATCH.sh runs without a shell level error",
                        result.returncode == 0,
                        result.stderr.strip()[-300:] if result.returncode else "")

            old_creds = dict(throwaway)
            probe = st_client.client_from_config(old_creds)
            try:
                probe.login()
                c.check("the old password no longer works after the PATCH", False)
                probe.logout()
            except st_client.STError as e:
                c.check("the old password no longer works after the PATCH",
                        e.status == 401, e.status)

            new_creds = dict(throwaway)
            new_creds["st_password"] = NEW_PASSWORD
            probe2 = st_client.client_from_config(new_creds)
            new_works = False
            try:
                probe2.login()
                new_works = True
                probe2.logout()
            except st_client.STError:
                pass
            c.check("the new password from the script's own payload now works", new_works)

finally:
    if created:
        client.delete("administrators/" + NAME)
        c.check('the throwaway administrator "%s" was removed' % NAME,
                not client.exists("administrators/" + NAME))
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own curl calls)"
       % client.calls)

sys.exit(c.done())
