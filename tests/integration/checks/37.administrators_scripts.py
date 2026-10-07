#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 20.AdministrativeRoles and
21.Administrators examples: creates the role example_role and the
administrator example_admin that holds it, reads, locks, unlocks and changes
them, creates an API key, calls the API with the key alone, revokes it and
checks it is refused, then deletes the administrator and the role.

Each step is confirmed through the API, not from the scripts' output alone.
Refuses to start when example_role or example_admin already exist, and
removes both in a finally block, whatever happens.

Needs --write and st_allow_writes="yes".
"""
import os
import re
import secrets
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the administrator examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Roles and administrators, run for real from Admin/API 2.0/bash/20 and 21")
BASH = runner.path("Admin", "API 2.0", "bash")
ROLE, ADMIN = "example_role", "example_admin"


def script(folder, name, args=None, expect_rc=0):
    result = runner.run(os.path.join(BASH, folder, name), args, timeout=60)
    out = result.stdout + result.stderr
    c.check("%s exits %s" % (name, expect_rc), result.returncode == expect_rc, out.strip()[-300:])
    return out


def roles(name, args=None, expect_rc=0):
    return script("20.AdministrativeRoles", name, args, expect_rc)


def admins(name, args=None, expect_rc=0):
    return script("21.Administrators", name, args, expect_rc)


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /administrativeRoles or /administrators")
    admin.logout()
    sys.exit(c.done())
if admin.exists("administrativeRoles/" + ROLE) or admin.exists("administrators/" + ADMIN):
    c.check("%s and %s do not exist yet" % (ROLE, ADMIN), False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

os.environ["ADMIN_PASSWORD"] = "Ex-%s!aA1" % secrets.token_hex(8)
try:
    with runner.real_credentials(BASH, config):
        # --- the role
        roles("02.administrativeRoles_POST.sh")
        role = admin.get("administrativeRoles/" + ROLE).json() or {}
        c.check("02 created a limited role that opens Change Password",
                role.get("isLimited") is True and role.get("menus") == ["Change Password"], role)
        out = roles("01.administrativeRoles_GET.sh")
        c.check("01 lists it with its menus", "  %s: Change Password" % ROLE in out, out[-300:])
        out = roles("03.administrativeRoles_name_HEAD.sh")
        c.check("03 finds it", "The role %s exists." % ROLE in out, out[-200:])
        roles("06.administrativeRoles_name_PATCH.sh")
        menus = (admin.get("administrativeRoles/" + ROLE).json() or {}).get("menus")
        c.check("06 PATCH added File Tracking (the server keeps no order)",
                sorted(menus or []) == ["Change Password", "File Tracking"], menus)
        roles("05.administrativeRoles_name_PUT.sh")
        menus = (admin.get("administrativeRoles/" + ROLE).json() or {}).get("menus")
        c.check("05 PUT replaced the menus", sorted(menus or []) == ["Audit Log", "Change Password"], menus)

        # --- the administrator
        admins("02.administrators_POST.sh")
        new = admin.get("administrators/" + ADMIN).json() or {}
        c.check("02 created it, holding the role, under ST_USER",
                (new.get("roleName"), new.get("parent")) == (ROLE, config.get("st_user")), new.get("parent"))
        out = roles("04.administrativeRoles_name_GET.sh")
        c.check("04 role GET lists it as a member", "\n  %s" % ADMIN in out, out[-300:])
        # the server's own members link finds nobody for a name with a space
        own_role = (admin.get("administrators/" + config["st_user"]).json() or {}).get("roleName")
        if own_role:
            out = roles("04.administrativeRoles_name_GET.sh", [own_role])
            c.check("04 role GET lists %s under its own role, %s" % (config["st_user"], own_role),
                    "\n  %s\n" % config["st_user"] in out + "\n", out[-300:])
        out = admins("01.administrators_GET.sh", [ROLE])
        c.check("01 lists it among the role's holders", "  %s  created by" % ADMIN in out, out[-300:])
        out = admins("03.administrators_name_HEAD.sh")
        c.check("03 finds it", "The administrator %s exists." % ADMIN in out, out[-200:])
        out = admins("04.administrators_name_GET.sh")
        c.check("04 prints the summary", "  %s, role %s" % (ADMIN, ROLE) in out, out[-300:])

        admins("06.administrators_name_PATCH.sh")
        c.check("06 PATCH locked it", (admin.get("administrators/" + ADMIN).json() or {}).get("locked") is True)
        admins("05.administrators_name_PUT.sh")
        c.check("05 PUT unlocked it", (admin.get("administrators/" + ADMIN).json() or {}).get("locked") is False)

        # --- an API key
        out = admins("08.administrators_name_apiKeys_POST.sh", ["1", "read"])
        key = re.search(r"The key, shown this once: (\S+)", out)
        c.check("08 printed the key", bool(key), out[-200:])
        keys = admin.get("administrators/%s/api-keys" % ADMIN).json() or []
        c.check("08 created one read key", [k.get("permissions") for k in keys] == [["read"]], keys)
        if key:
            out = admins("09.administrators_name_apiKeys_GET.sh", [key.group(1)])
            c.check("09 lists the key by id", keys and ("  %s  " % keys[0].get("id")) in out, out[-300:])
            c.check("09 the key alone logs in as the administrator", "  %s, role %s" % (ADMIN, ROLE) in out, out[-200:])
        admins("10.administrators_name_apiKeys_keyId_DELETE.sh")
        c.check("10 revoked every key", (admin.get("administrators/%s/api-keys" % ADMIN).json() or []) == [])
        if key:
            out = admins("09.administrators_name_apiKeys_GET.sh", [key.group(1)], expect_rc=1)
            c.check("09 a revoked key is refused with 401", "The key was refused (HTTP 401)" in out, out[-200:])

        # --- clean up through the examples: the role first, its member moved to
        # another limited role (one with a space in its name, when there is one)
        limited = [r["roleName"] for r in (admin.get("administrativeRoles", params={"isLimited": "true"}).json()
                                           or {}).get("result", []) if r.get("roleName") != ROLE]
        target = next((r for r in limited if " " in r), limited[0] if limited else None)
        if target:
            roles("07.administrativeRoles_name_DELETE.sh", [target])
            c.check("07 deleted the role", not admin.exists("administrativeRoles/" + ROLE))
            moved = (admin.get("administrators/" + ADMIN).json() or {}).get("roleName")
            c.check("07 moved its administrator to %s" % target, moved == target, moved)
        else:
            c.info("no other limited role to move the administrator to")
        admins("07.administrators_name_DELETE.sh")
        c.check("07 deleted the administrator", not admin.exists("administrators/" + ADMIN))
        if not target:
            roles("07.administrativeRoles_name_DELETE.sh")
            c.check("07 deleted the role", not admin.exists("administrativeRoles/" + ROLE))
finally:
    if admin.exists("administrators/" + ADMIN):
        admin.delete("administrators/" + ADMIN)
    if admin.exists("administrativeRoles/" + ROLE):
        admin.delete("administrativeRoles/" + ROLE)
    c.check("nothing is left behind",
            not admin.exists("administrators/" + ADMIN) and not admin.exists("administrativeRoles/" + ROLE))
    admin.logout()

sys.exit(c.done())
