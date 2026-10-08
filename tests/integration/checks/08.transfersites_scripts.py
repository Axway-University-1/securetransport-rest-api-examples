#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified
Admin/API 2.0/bash/06.TransferSites/01.sites_POST.sh against a configured
server, and independently verifies it through the API.

This check verifies the real POST script (01) and then cleans up directly
through the API, the same as the business units check. The other examples of
the folder are run by 31 (02 to 04) and 54 (05 to 11).

A site is addressed by a server generated id, not by its name - confirmed
against a real server: GET /sites?name=HTTP&account=john returns the id to
delete, rather than the site being reachable as /sites/HTTP.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.

Objects touched, by the literal values the script uses: a site named "HTTP",
attached to the account "john", which must already exist.

Safety: never touches a site named "HTTP" on account "john" that already
exists - confirmed to matter in practice: it does on at least one real server
this was tested against. Rather than skip outright in that case, this check
creates a throwaway site named "HTTP_test" on the same, unmodified "john"
account instead - attaching a new site does not change the account itself -
using a name-substituted copy of 01.sites_POST.sh (script_runner.substituted_copy).
That is not the same as running the real file - the same request body is
sent, under a site name that does not collide, but it is a modified copy, and
is reported as such rather than as the literal script.
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
    st_client.skip("read only run, pass --write to run the transfer sites script for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Transfer Sites, run for real from Admin/API 2.0/bash/06.TransferSites")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
SITES_DIR = os.path.join(BASH_TREE, "06.TransferSites")
NAME = "HTTP"
ACCOUNT = "john"


def find_site(client, name=NAME):
    """The site's id, or None. Sites are addressed by id, not by name."""
    response = client.get("sites", params={"name": name})
    for site in (response.json() or {}).get("result", []):
        if site.get("account") == ACCOUNT:
            return site
    return None


client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /sites; run this against a "
           "real server to exercise it")
    client.logout()
    sys.exit(c.done())

created_id = None
target_name = NAME
fallback = False

try:
    if not client.exists("accounts/" + ACCOUNT):
        c.info('the account "%s" this script attaches the site to does not '
               "exist on this server; skipping, since the script itself "
               "documents that account as a prerequisite" % ACCOUNT)
    else:
        if find_site(client):
            target_name = NAME + "_test"
            fallback = True
            if find_site(client, target_name):
                c.info('a site named "%s" on account "%s" already exists on '
                       'this server, and so does "%s"; skipping this check '
                       "rather than risk touching either one."
                       % (NAME, ACCOUNT, target_name))
                target_name = None
            else:
                c.info('a site named "%s" on account "%s" already exists on '
                       'this server; using a throwaway "%s" instead, on the '
                       "same unmodified account, via a name-substituted copy "
                       "of 01.sites_POST.sh - see this check's own docstring "
                       "for what that does and does not prove."
                       % (NAME, ACCOUNT, target_name))

        if target_name:
            script_path = os.path.join(SITES_DIR, "01.sites_POST.sh")
            with runner.real_credentials(BASH_TREE, config):
                if fallback:
                    subs = {'SITE_NAME="%s"' % NAME: 'SITE_NAME="%s"' % target_name}
                    with runner.substituted_copy(script_path, subs) as copy:
                        with open(copy) as f:
                            c.check("the copy of 01.sites_POST.sh names the site %s, not %s" % (target_name, NAME),
                                    'SITE_NAME="%s"' % target_name in f.read())
                        result = runner.run(copy)
                else:
                    result = runner.run(script_path)
                c.check("01.sites_POST.sh runs without a shell level error",
                        result.returncode == 0,
                        result.stderr.strip()[-300:] if result.returncode else "")

            label = " (name-substituted copy)" if fallback else ""
            site = find_site(client, target_name)
            c.check('a site named "%s" on account "%s" now exists%s'
                    % (target_name, ACCOUNT, label), site is not None)
            if site:
                created_id = site.get("id")
                c.check("the site's protocol matches the script" + label,
                        site.get("protocol") == "http", site.get("protocol"))
                c.check("the site's host is this server, as the script sets it" + label,
                        site.get("host") == config.get("st_server"), site.get("host"))

finally:
    if created_id:
        response = client.delete("sites/" + created_id)
        c.check("DELETE /sites/%s returns 204" % created_id, response.status == 204,
                response.status)
        c.check("the site is gone afterward", find_site(client, target_name) is None)
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own curl calls)"
       % client.calls)

sys.exit(c.done())
