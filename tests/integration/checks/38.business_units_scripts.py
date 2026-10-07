#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 12.BusinessUnits examples 02
to 07 (07.businessunits_scripts.py covers 01) against throwaway business
units: "example_bu", and "example bu child" nested under it, with one account
in the child. Lists, checks and reads them, counts the account, changes two
properties with PUT and PATCH, sees the delete refused while the unit still
has a nested unit or an account, then deletes both.

The child's name has a space on purpose: the server's own metadata links are
encoded wrongly for such a name, and the examples must not rely on them.

Never touches a business unit it did not create: refuses to start when any of
the three objects exist, and removes them in a finally block, whatever
happens. Needs --write and st_allow_writes="yes".
"""
import os
import secrets
import sys
from urllib.parse import quote

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the business unit examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Business units, run for real from Admin/API 2.0/bash/12.BusinessUnits (02 to 07)")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "12.BusinessUnits")
PARENT, CHILD, ACCOUNT = "example_bu", "example bu child", "example_bu_user"


def bu_path(name):
    return "businessUnits/" + quote(name, safe="")


def script(name, args=None, expect_rc=0):
    result = runner.run(os.path.join(FOLDER, name), args, timeout=60)
    out = result.stdout + result.stderr
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc,
            out.strip()[-300:])
    return out


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /businessUnits")
    admin.logout()
    sys.exit(c.done())
if admin.exists(bu_path(PARENT)) or admin.exists(bu_path(CHILD)) or admin.exists("accounts/" + ACCOUNT):
    c.check("%s, %s and %s do not exist yet" % (PARENT, CHILD, ACCOUNT), False,
            "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

try:
    c.check("set up: the parent unit", admin.post("businessUnits", {"name": PARENT, "baseFolder": "/home/example_bu"}).status == 201)
    c.check("set up: the nested unit", admin.post("businessUnits", {"name": CHILD, "baseFolder": "/home/example_bu/child",
                                                                     "parent": PARENT}).status == 201)
    c.check("set up: an account in the nested unit", admin.post("accounts", {
        "name": ACCOUNT, "type": "user", "homeFolder": "/home/example_bu/child/" + ACCOUNT, "businessUnit": CHILD,
        "uid": "10001", "gid": "10001",
        "user": {"name": ACCOUNT, "passwordCredentials": {"password": "Ex-%s!aA1" % secrets.token_hex(8)}}}).status == 201)

    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        out = script("02.businessUnits_GET.sh", ["example*", PARENT])
        c.check("02 lists the nested unit by its hierarchy", "  %s/%s  /home/example_bu/child" % (PARENT, CHILD) in out, out[-300:])
        c.check("02 lists it under its parent", out.rstrip().endswith("  " + CHILD), out[-200:])
        out = script("03.businessUnits_name_HEAD.sh", [CHILD])
        c.check("03 finds the unit with a space in its name", "The business unit %s exists." % CHILD in out, out[-200:])
        out = script("04.businessUnits_name_GET.sh", [CHILD])
        c.check("04 counts the account in the unit with a space in its name", "  accounts in it: 1" in out, out[-200:])

        script("05.businessUnits_name_PUT.sh", [PARENT])
        c.check("05 PUT set homeFolderModifyingAllowed",
                (admin.get(bu_path(PARENT)).json() or {}).get("homeFolderModifyingAllowed") is True)
        script("06.businessUnits_name_PATCH.sh", [PARENT, "false"])
        c.check("06 PATCH set sharedFoldersCollaborationAllowed",
                (admin.get(bu_path(PARENT)).json() or {}).get("sharedFoldersCollaborationAllowed") is False)

        out = script("07.businessUnits_name_DELETE.sh", [PARENT], expect_rc=1)
        c.check("07 a unit with a nested unit is refused, and says why", "nested business units" in out, out[-200:])
        out = script("07.businessUnits_name_DELETE.sh", [CHILD], expect_rc=1)
        c.check("07 a unit with an account is refused, and says why", "associated with some account" in out, out[-200:])
        c.check("07 nothing was deleted on a refusal", admin.exists(bu_path(PARENT)) and admin.exists(bu_path(CHILD)))

        admin.delete("accounts/" + ACCOUNT)
        script("07.businessUnits_name_DELETE.sh", [CHILD])
        script("07.businessUnits_name_DELETE.sh", [PARENT])
        c.check("07 deleted both units", not admin.exists(bu_path(CHILD)) and not admin.exists(bu_path(PARENT)))
finally:
    if admin.exists("accounts/" + ACCOUNT):
        admin.delete("accounts/" + ACCOUNT)
    for name in (CHILD, PARENT):
        if admin.exists(bu_path(name)):
            admin.delete(bu_path(name))
    c.check("nothing is left behind", not any(admin.exists(p) for p in
                                              ("accounts/" + ACCOUNT, bu_path(CHILD), bu_path(PARENT))))
    admin.logout()

sys.exit(c.done())
