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
instead. The script takes the name and the base folder as arguments (its
defaults, Finance and /home/fin, are what it creates bare), so this runs the
real, unmodified file with other arguments: no copy of it is made. The script
exits 1 on a refusal, so the exit code is checked as well, and so is that a
second run (the name exists now) is refused with exit 1 and changes nothing.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the business units script for real")

c = st_client.Checker("Business Units, run for real from Admin/API 2.0/bash/12.BusinessUnits")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
BU_DIR = os.path.join(BASH_TREE, "12.BusinessUnits")
NAME = "Finance"

client = harness.connect(config, c, mock=("the bundled mock does not implement /businessUnits; run this "
                                          "against a real server to exercise it"))

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
                   'creating a throwaway "%s" instead, with the script\'s own arguments.' % (NAME, target))

    if target:
        with runner.real_credentials(BASH_TREE, config):
            script_path = os.path.join(BU_DIR, "01.businessUnits_POST.sh")
            if fallback:
                result = runner.run(script_path, [target, "/home/" + target])
            else:
                result = runner.run(script_path)
            c.check("01.businessUnits_POST.sh creates it, prints HTTP 201 and exits 0",
                    result.returncode == 0 and "HTTP 201" in result.stdout,
                    (result.stdout + result.stderr).strip()[-300:])
            again = runner.run(script_path, [target, "/home/" + target] if fallback else None)
            c.check("01.businessUnits_POST.sh run again is refused (HTTP 400), exit 1",
                    again.returncode == 1 and "HTTP 400" in again.stdout, (again.stdout + again.stderr).strip()[-300:])

        label = ""
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
