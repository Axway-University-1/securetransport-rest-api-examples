#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs EndUser/UseCases/01-authentication for real, as a
throwaway end user account this check creates (with a password only it knows)
and removes at the end: Basic authentication on one call, a call with no
credentials (401), the login and its cookie jar and csrfToken, the call with the
cookie only, the csrfToken header, the recovery from an expired session, and the
logout, after which the cookie that was just ended is refused.

Then it runs 00.run_all.sh and 99.cleanup_DELETE.sh, and checks that no
session.cookie.jar or state.local.csrf is left in the use case folder.

Needs --write and st_allow_writes="yes". The end user port is the one the other
EndUser checks use (st_enduser_port, or one less than the admin port).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the EndUser use cases for real")

c = st_client.Checker("EndUser use case 01-authentication, run for real")

ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
UC = runner.path("EndUser", "UseCases", "01-authentication")
ACCOUNT = config.get("st_enduser_test_account", "ZZTEST_enduser") + "_uc"
ACCOUNT_PASSWORD = harness.new_password()
ENDUSER_PORT = harness.ports(config).enduser

admin = harness.connect(config, c, mock=("the bundled mock does not implement the EndUser API on a second port; "
                                         "run this against a real server to exercise it"))
created = False
JAR = os.path.join(UC, "session.cookie.jar")
CSRF = os.path.join(UC, "state.local.csrf")


def step(name, expect_rc=0):
    r = runner.run(os.path.join(UC, name))
    c.check("%s exits %d" % (name, expect_rc), r.returncode == expect_rc,
            (r.stdout + r.stderr).strip()[-300:])
    return r


try:
    if admin.exists("accounts/" + ACCOUNT):
        c.info('an account named "%s" already exists; skipping rather than reuse it' % ACCOUNT)
        admin.logout()
        sys.exit(c.done())
    response = admin.post("accounts", {
        "name": ACCOUNT, "type": "user", "uid": "1051", "gid": "1051",
        "homeFolder": "/home/" + ACCOUNT,
        "user": {"name": ACCOUNT, "passwordCredentials": {"password": ACCOUNT_PASSWORD}},
    })
    created = response.status == 201
    c.check('created a throwaway end user account "%s"' % ACCOUNT, created, response.text[:200])
    if not created:
        admin.logout()
        sys.exit(c.done())

    eu_config = dict(config, st_port=ENDUSER_PORT, st_user=ACCOUNT, st_password=ACCOUNT_PASSWORD)
    with runner.real_credentials(ENDUSER_TREE, eu_config):
        r = step("01.basic_auth_GET_myself.sh")
        c.check("01 names the account it asked about", ACCOUNT in r.stdout, r.stdout[-200:])
        r = step("02.no_credentials_GET_myself.sh")
        c.check("02 saw the 401", "HTTP 401" in r.stdout, r.stdout[-200:])
        step("03.session_login_POST.sh")
        c.check("03 left a cookie jar", os.path.exists(JAR))
        c.check("03 left a csrfToken", os.path.exists(CSRF) and os.path.getsize(CSRF) > 0)
        step("04.session_cookie_GET_myself.sh")
        step("05.session_csrf_header_GET_myself.sh")
        step("06.session_expired_recovery.sh")
        c.check("06 ended with a session again", os.path.exists(JAR))
        step("07.logout_DELETE.sh")
        c.check("07 removed the jar", not os.path.exists(JAR))
        step("07.logout_DELETE.sh", expect_rc=2)

        r = runner.run(os.path.join(UC, "00.run_all.sh"), timeout=180)
        c.check("00.run_all.sh exits 0", r.returncode == 0, (r.stdout + r.stderr).strip()[-300:])
        step("99.cleanup_DELETE.sh")
        c.check("99 left no jar and no token", not os.path.exists(JAR) and not os.path.exists(CSRF))
finally:
    for p in (JAR, CSRF):
        if os.path.exists(p):
            os.remove(p)
    if created:
        admin.delete("accounts/" + ACCOUNT)
        c.check('the throwaway account "%s" was removed' % ACCOUNT, not admin.exists("accounts/" + ACCOUNT))
    admin.logout()

sys.exit(c.done())
