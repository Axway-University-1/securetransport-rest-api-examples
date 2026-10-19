#!/usr/bin/env python3
"""
WRITES TO THE SERVER (one thing, and it puts back what it finds). Runs Admin/UseCases
01-authentication and 02-knowing-the-server for real, as the administrator of the
configuration.

01-authentication logs in, calls with the cookie and without credentials, and PATCHes
/myself with the value /preferredFileTrackingColumns already has: this check reads it
before and after through its own session and asserts it is the same. It also checks that
no session.cookie.jar, state.local.csrf or API key file is left in either folder, and that
99.cleanup_DELETE.sh can be run a second time with nothing to remove (exit 0).

02-knowing-the-server only reads: 00.run_all.sh must exit 0 and its output must agree with
what this check reads itself (the release from /version, the number of servers from /servers).

The API key steps (08 to 10) make one read-only key of one day for the administrator and revoke it, by its
id; the check lists the administrator's keys before and after and asserts the list is the same, so a key the
administrator had before is never touched.

Needs --write and st_allow_writes="yes", for the one PATCH and the key.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the Admin use cases for real")

c = st_client.Checker("Admin use cases 01 and 02, run for real")

ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
USE_CASES = runner.path("Admin", "UseCases")
NAMES = ("01-authentication", "02-knowing-the-server")
STATE_FILES = ("session.cookie.jar", "state.local.csrf", "state.local.apikey", "state.local.apikey_id")

admin = harness.connect(config, c, mock=("the bundled mock does not implement the whole set these use cases read; "
                                         "run this against a real server to exercise it"))


def clear_local():
    for name in NAMES:
        for leftover in STATE_FILES:
            p = os.path.join(USE_CASES, name, leftover)
            if os.path.exists(p):
                os.remove(p)


try:
    columns_before = admin.get("myself").json().get("preferredFileTrackingColumns")
    version = admin.get("version").json().get("version")
    admin_name = config["st_user"]

    def key_ids():
        return sorted(k["id"] for k in (admin.get("administrators/%s/api-keys" % admin_name).json() or []))

    keys_before = key_ids()
    servers = admin.get("servers").json().get("resultSet", {}).get("totalCount")

    with runner.real_credentials(ADMIN_TREE, config):
        for name in NAMES:
            r = runner.run(os.path.join(USE_CASES, name, "00.run_all.sh"), timeout=300)
            c.check("%s: 00.run_all.sh exits 0" % name, r.returncode == 0, (r.stdout + r.stderr).strip()[-400:])
            c.check("%s: it ended with the cleanup" % name, "Cleaned up." in r.stdout, r.stdout[-200:])
            if name == "02-knowing-the-server":
                c.check("02: the release it printed is the one /version says", "Release: %s " % version in r.stdout, version)
                c.check("02: the number of servers it printed is the one /servers says",
                        "Servers: %s of %s" % (servers, servers) in r.stdout, servers)
            r = runner.run(os.path.join(USE_CASES, name, "99.cleanup_DELETE.sh"))
            c.check("%s: 99.cleanup_DELETE.sh a second time, with nothing to remove, exits 0" % name, r.returncode == 0)
            for leftover in STATE_FILES:
                c.check("%s: no %s is left" % (name, leftover), not os.path.exists(os.path.join(USE_CASES, name, leftover)))

        # 01 step by step: what the server says, not only what the script prints
        uc = os.path.join(USE_CASES, "01-authentication")
        r = runner.run(os.path.join(uc, "04.session_cookie_GET_myself.sh"))
        c.check("01/04 with no session says to log in first and exits 2", r.returncode == 2, r.returncode)
        r = runner.run(os.path.join(uc, "03.session_login_POST.sh"))
        c.check("01/03 exits 0", r.returncode == 0, (r.stdout + r.stderr).strip()[-300:])
        c.check("01/03 left a csrfToken", os.path.getsize(os.path.join(uc, "state.local.csrf")) > 0)
        r = runner.run(os.path.join(uc, "05.session_csrf_header_PATCH_myself.sh"))
        c.check("01/05 exits 0", r.returncode == 0, (r.stdout + r.stderr).strip()[-300:])
        c.check("01/05 names the option that says whether the token is enforced",
                "Webservices.Admin.CsrfToken.enabled = " in r.stdout, r.stdout[-300:])
        r = runner.run(os.path.join(uc, "07.logout_DELETE.sh"))
        c.check("01/07 exits 0 and the old cookie is refused", r.returncode == 0 and "The session is over." in r.stdout, r.stdout[-200:])
        r = runner.run(os.path.join(uc, "08.apikey_POST.sh"))
        c.check("01/08 makes a key", r.returncode == 0 and os.path.getsize(os.path.join(uc, "state.local.apikey")) > 0,
                (r.stdout + r.stderr)[-300:])
        c.check("01/08 the administrator holds one key more while it exists", len(key_ids()) == len(keys_before) + 1, (keys_before, key_ids()))
        r = runner.run(os.path.join(uc, "09.apikey_GET_myself.sh"))
        c.check("01/09 reads with the key alone (200) and is refused a write (403)",
                r.returncode == 0 and "HTTP 200" in r.stdout and "HTTP 403" in r.stdout, r.stdout[-300:])
        r = runner.run(os.path.join(uc, "10.apikey_DELETE.sh"))
        c.check("01/10 revokes it, and the key is refused afterwards (401)", r.returncode == 0 and "The key is dead." in r.stdout, r.stdout[-300:])
        c.check("01/10 the administrator is back to the keys it had", key_ids() == keys_before, (keys_before, key_ids()))
        # a key left behind is revoked by the cleanup
        runner.run(os.path.join(uc, "08.apikey_POST.sh"))
        r = runner.run(os.path.join(uc, "99.cleanup_DELETE.sh"))
        c.check("01/99 revokes a key that is left, and only that one", r.returncode == 0 and key_ids() == keys_before, (keys_before, key_ids()))
        runner.run(os.path.join(uc, "99.cleanup_DELETE.sh"))

    c.check("none of the administrator's own API keys was touched", key_ids() == keys_before, (keys_before, key_ids()))
    columns_after = admin.get("myself").json().get("preferredFileTrackingColumns")
    c.check("the administrator's preferredFileTrackingColumns is exactly what it was", columns_before == columns_after)
finally:
    clear_local()
    admin.logout()

sys.exit(c.done())
