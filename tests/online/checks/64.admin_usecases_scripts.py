#!/usr/bin/env python3
"""
WRITES TO THE SERVER (one thing, and it puts back what it finds). Runs Admin/UseCases
01-authentication, 02-knowing-the-server and 03-onboard-a-user-account for real, as the administrator of the
configuration.

01-authentication logs in, calls with the cookie and without credentials, and PATCHes
/myself with the value /preferredFileTrackingColumns already has: this check reads it
before and after through its own session and asserts it is the same. It also checks that
no session.cookie.jar, state.local.csrf or API key file is left in either folder, and that
99.cleanup_DELETE.sh can be run a second time with nothing to remove (exit 0).

02-knowing-the-server only reads: 00.run_all.sh must exit 0 and its output must agree with
what this check reads itself (the release from /version, the number of servers from /servers).

03-onboard-a-user-account makes a throwaway account (example_onb_<random>), and the check proves what each step did through
the API on its own: the email address after 03, the folder and the file after 05 (read as the user), the account gone after 06, the
home folder emptied and still usable by a new account of the same name (the same user id: the lesson of 06), a second 01 refused
while the account exists, and that nothing is left after 99 (no account, nothing in the home, no state file).

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
NAMES = ("01-authentication", "02-knowing-the-server", "03-onboard-a-user-account")
STATE_FILES = ("session.cookie.jar", "state.local.csrf", "state.local.apikey", "state.local.apikey_id", "state.local.password")

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
        for name in NAMES[:2]:
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

        # ---- 03-onboard-a-user-account: a throwaway account, step by step ----------------------------------------------
        uc3 = os.path.join(USE_CASES, "03-onboard-a-user-account")
        eu_port = harness.ports(config).enduser
        env3 = {"ST_ENDUSER_PORT": eu_port}
        onboard = "example_onb_" + harness.suffix(6).lower()
        try:
            def step(script, *args):
                return runner.run(os.path.join(uc3, script), [onboard] + list(args), timeout=300, env=env3)

            def home(user_password):
                eu = st_client.EndUserClient(config["st_server"], eu_port, onboard, user_password)
                response = eu.login_response()
                if response.status != 200:
                    return None
                try:
                    listed = eu.list_files().json() or {}
                    return [f.get("fileName") for f in listed.get("files", [])]
                finally:
                    eu.logout()

            r = step("01.accounts_POST.sh")
            c.check("03/01 makes the account (exit 0)", r.returncode == 0 and "HTTP 201" in r.stdout, (r.stdout + r.stderr)[-300:])
            made = admin.get("accounts/" + onboard)
            c.check("03/01 the account is there, with the home folder and the email it was given",
                    made.status == 200 and made.json().get("homeFolder") == "/home/" + onboard
                    and made.json().get("contact", {}).get("email") == onboard + "@example.com", made.text[:200])
            uid_first = made.json().get("uid") if made.status == 200 else None
            password = open(os.path.join(uc3, "state.local.password")).read() if os.path.exists(os.path.join(uc3, "state.local.password")) else ""
            c.check("03/01 keeps the password of the account in state.local.password", len(password) > 8)
            r = step("01.accounts_POST.sh")
            c.check("03/01 a second run is refused (exit 1) and says the account exists", r.returncode == 1 and "already exists" in r.stdout, r.stdout[-200:])
            r = step("02.accounts_GET.sh")
            c.check("03/02 reads it back and shows the home folder and that the password is not returned",
                    r.returncode == 0 and "/home/" + onboard in r.stdout and "the password is never returned" in r.stdout, r.stdout[-300:])
            r = step("03.accounts_PATCH.sh")
            c.check("03/03 changes the email address (exit 0)", r.returncode == 0 and "Changed, and nothing else was touched." in r.stdout, r.stdout[-300:])
            c.check("03/03 the server has the new address, and the home folder is as it was",
                    admin.get("accounts/" + onboard).json().get("contact", {}).get("email") == onboard + "_changed@example.com"
                    and admin.get("accounts/" + onboard).json().get("homeFolder") == "/home/" + onboard)
            r = step("04.enduser_login_GET.sh")
            c.check("03/04 logs in as the user on the End User API, and a wrong password is refused",
                    r.returncode == 0 and "Logged in as %s" % onboard in r.stdout and "Refused, as it should be." in r.stdout, (r.stdout + r.stderr)[-300:])
            c.check("03/04 sent one wrong password only: the account is not locked",
                    admin.get("accounts/" + onboard).json().get("user", {}).get("locked") is False)
            r = step("05.enduser_home_POST.sh")
            c.check("03/05 makes a folder and uploads a file (exit 0)", r.returncode == 0 and "hello.txt" in r.stdout, (r.stdout + r.stderr)[-300:])
            c.check("03/05 the user sees the folder welcome in the home, read through the API",
                    "welcome" in (home(password) or []), home(password))
            r = step("06.accounts_DELETE.sh")
            c.check("03/06 deletes the account (exit 0) and says the home folder stays",
                    r.returncode == 0 and "DELETE: HTTP 204" in r.stdout and "GET: HTTP 404" in r.stdout and "Its home folder /home/%s is not" % onboard in r.stdout,
                    r.stdout[-400:])
            c.check("03/06 the account is gone", admin.get("accounts/" + onboard).status == 404)
            c.check("03/06 the home folder was emptied first: it said how many entries it removed", "Emptied the home folder of %s: 2 entries removed." % onboard in r.stdout, r.stdout[-400:])
            # the same name again gets the same user id, so the home that stayed is still its own: it is empty, and usable
            r = step("01.accounts_POST.sh")
            c.check("03 the same name again is made (exit 0)", r.returncode == 0, r.stdout[-300:])
            again = admin.get("accounts/" + onboard).json() if admin.exists("accounts/" + onboard) else {}
            c.check("03 it gets the same user id as the first time (that is what keeps the home usable)", again.get("uid") == uid_first, (uid_first, again.get("uid")))
            password = open(os.path.join(uc3, "state.local.password")).read()
            c.check("03 its home folder is empty: step 06 emptied it", home(password) == [], home(password))
            r = step("05.enduser_home_POST.sh")
            c.check("03 a folder can be made in the home that stayed (the user id is the same)", r.returncode == 0, (r.stdout + r.stderr)[-300:])
            r = runner.run(os.path.join(uc3, "00.run_all.sh"), ["real_account"], timeout=60, env=env3)
            c.check("03/00 a name that does not start with example_ is refused at once (exit 2) and touches nothing", r.returncode == 2 and "Usage: ./00.run_all.sh" in r.stdout, r.stdout[-200:])
            r = step("99.cleanup_DELETE.sh")
            c.check("03/99 removes the account and ends the session (exit 0)", r.returncode == 0 and "The account %s was deleted." % onboard in r.stdout, r.stdout[-300:])
            c.check("03/99 no account is left", admin.get("accounts/" + onboard).status == 404)
            r = step("99.cleanup_DELETE.sh")
            c.check("03/99 a second time, with nothing to remove, exits 0", r.returncode == 0 and "nothing to delete" in r.stdout, r.stdout[-200:])
            r = runner.run(os.path.join(uc3, "00.run_all.sh"), [onboard], timeout=300, env=env3)
            c.check("03/00 the whole use case, from start to cleanup, exits 0", r.returncode == 0 and "Cleaned up." in r.stdout, (r.stdout + r.stderr)[-400:])
            c.check("03/00 and leaves no account", admin.get("accounts/" + onboard).status == 404)
            for leftover in STATE_FILES:
                c.check("03: no %s is left" % leftover, not os.path.exists(os.path.join(uc3, leftover)))
        finally:
            if admin.exists("accounts/" + onboard):
                step("99.cleanup_DELETE.sh")
            if admin.exists("accounts/" + onboard):
                admin.delete("accounts/" + onboard)
                c.info("the account %s was removed by hand" % onboard)

    c.check("none of the administrator's own API keys was touched", key_ids() == keys_before, (keys_before, key_ids()))
    columns_after = admin.get("myself").json().get("preferredFileTrackingColumns")
    c.check("the administrator's preferredFileTrackingColumns is exactly what it was", columns_before == columns_after)
finally:
    clear_local()
    admin.logout()

sys.exit(c.done())
