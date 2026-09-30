#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified
Admin/API 2.0/bash/12.BusinessUnits/01.businessUnits_POST.sh against a
configured server, and independently verifies it through the API.

This folder has only a POST example - no GET, HEAD, PATCH or DELETE example
exists for business units. Rather than invent new shipped examples (a
different task from testing the ones that exist), this check verifies the
real POST script and then cleans up directly through the API.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.

Objects touched, by the literal name the script uses: "Finance"

Safety: never touches a business unit named "Finance" that already exists -
confirmed to matter in practice: it does on at least one real server this was
tested against. A business unit can own accounts and folders on disk; treat
one that already exists as never disposable. Rather than skip outright in
that case, this check creates a throwaway "Finance_test" business unit
instead, and runs a name-substituted copy of 01.businessUnits_POST.sh
(script_runner.substituted_copy) to create it. That is not the same as
running the real file - the same request body is sent, under a name and
baseFolder that do not collide, but it is a modified copy, and is reported as
such rather than as the literal script.
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
    st_client.skip("read only run, pass --write to run the business units script for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Business Units, run for real from Admin/API 2.0/bash/12.BusinessUnits")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
BU_DIR = os.path.join(BASH_TREE, "12.BusinessUnits")
NAME = "Finance"

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /businessUnits; run this "
           "against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

created = False
target = NAME
fallback = False

try:
    if client.exists("businessUnits/" + NAME):
        target = NAME + "_test"
        fallback = True
        if client.exists("businessUnits/" + target):
            c.info('a business unit named "%s" already exists on this server, '
                   'and so does "%s"; skipping this check rather than risk '
                   "touching either one." % (NAME, target))
            target = None
        else:
            c.info('a business unit named "%s" already exists on this server; '
                   'using a throwaway "%s" instead and a name-substituted copy '
                   "of 01.businessUnits_POST.sh - see this check's own "
                   "docstring for what that does and does not prove." % (NAME, target))

    if target:
        with runner.real_credentials(BASH_TREE, config):
            script_path = os.path.join(BU_DIR, "01.businessUnits_POST.sh")
            if fallback:
                subs = {'"name":"Finance","baseFolder":"/home/fin"':
                        '"name":"%s","baseFolder":"/home/%s"' % (target, target)}
                with runner.substituted_copy(script_path, subs) as copy:
                    result = runner.run(copy)
            else:
                result = runner.run(script_path)
            c.check("01.businessUnits_POST.sh runs without a shell level error",
                    result.returncode == 0,
                    result.stderr.strip()[-300:] if result.returncode else "")

        label = " (name-substituted copy)" if fallback else ""
        response = client.get("businessUnits/" + target)
        created = response.status == 200
        c.check("GET /businessUnits/%s now returns 200%s" % (target, label), created)
        if created:
            bu = response.json() or {}
            expected_folder = "/home/fin" if not fallback else "/home/" + target
            c.check("baseFolder was set as the script specifies" + label,
                    bu.get("baseFolder") == expected_folder, bu.get("baseFolder"))
        listed = {b.get("name") for b in client.page("businessUnits")}
        c.check("%s is listed in GET /businessUnits%s" % (target, label), target in listed)

finally:
    if created:
        response = client.delete("businessUnits/" + target)
        c.check("DELETE /businessUnits/%s returns 204" % target, response.status == 204,
                response.status)
        c.check("%s is gone afterward" % target, not client.exists("businessUnits/" + target))
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own curl calls)"
       % client.calls)

sys.exit(c.done())
