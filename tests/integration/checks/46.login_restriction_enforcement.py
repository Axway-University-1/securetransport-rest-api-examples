#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Checks that a login restriction policy does what it says:
a policy that denies every address, assigned to a business unit, stops the
accounts of that unit logging in, and only them.

  1. Two throwaway end user accounts: one in a throwaway business unit, one in
     none. Both log in, over the EndUser API and over FTP, before any policy.
  2. The real 26.LoginRestrictionPolicies examples create the policy
     (DENY_THEN_ALLOW), add the rule that denies every address, and assign the
     policy to the business unit.
  3. The account in the unit must now be REFUSED, over both protocols, and the
     account outside it must still get in.
  4. The real example takes the unit away again, and the first account logs in.

THIS CHECK FAILS, BY DESIGN, ON THE LAB THE EXAMPLES WERE WRITTEN AGAINST. There,
step 3 does not hold: the account of the unit keeps logging in over FTP and the
EndUser API, immediately and two minutes later, with either policy type. The check
is here so that this is not forgotten: it fails until enforcement works, and then
it passes by itself. 45.login_restriction_policies_scripts.py covers the API
and stays green. Whatever makes a policy take effect on a server (a setting, a
restart) belongs in this check's set up, once it is known.

FTP needs the FTP daemon running (its port is read from the server list); without
it only the EndUser API is tried. Needs --write and st_allow_writes="yes". Refuses
to start when its example_lre* objects exist, and removes everything in a finally
block. No policy is ever made the default.
"""
import base64
import ftplib
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the login restriction enforcement check for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Login restriction policy enforcement, run for real with 26.LoginRestrictionPolicies")
ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
FOLDER = os.path.join(ADMIN_TREE, "26.LoginRestrictionPolicies")
POLICY, UNIT = "example_lre", "example_lre_bu"
IN_UNIT, OUTSIDE = "example_lre_user", "example_lre_other"
RUN = base64.b32encode(os.urandom(4)).decode().rstrip("=").lower()
PASSWORD = "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"
ENDUSER_PORT = config.get("st_enduser_port") or str(int(config["st_port"]) - 1)
HOST = config["st_server"]
WAIT_SECONDS = 20


def script(name, args=None, expect_rc=0):
    result = runner.run(os.path.join(FOLDER, name), args, timeout=90)
    out = result.stdout + result.stderr
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc, out.strip()[-300:])
    return out


def endpoint_login(account):
    """'ok', or a description of the refusal."""
    client = st_client.EndUserClient(HOST, ENDUSER_PORT, account, PASSWORD)
    response = client._request("POST", "myself", headers={"Authorization": "Basic " + client._auth})
    if response.status == 200:
        client.logout()
        return "ok"
    return "refused (HTTP %s)" % response.status


def ftp_login(account):
    try:
        ftp = ftplib.FTP()
        ftp.connect(HOST, ftp_port, timeout=15)
        ftp.login(account, PASSWORD)
        ftp.quit()
        return "ok"
    except ftplib.error_perm as e:
        return "refused (%s)" % str(e)[:40]
    except (OSError, EOFError, ftplib.Error) as e:
        return "error (%s)" % type(e).__name__


def login_until(account, how, wanted, seconds=WAIT_SECONDS):
    """The login's outcome, waiting up to `seconds` for it to become `wanted` ('ok' or 'refused')."""
    deadline = time.time() + seconds
    while True:
        outcome = how(account)
        if outcome.startswith(wanted) or time.time() >= deadline:
            return outcome
        time.sleep(2)


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /loginRestrictionPolicies or the protocol servers")
    admin.logout()
    sys.exit(c.done())

servers = admin.get("servers").json()
ftp_servers = [s for s in (servers if isinstance(servers, list) else servers.get("result", [])) if s.get("protocol") == "ftp" and s.get("port")]
ftp_port = ftp_servers[0]["port"] if ftp_servers and admin.get("daemons").json().get("ftpStatus") == "Running" else None
protocols = [("the EndUser API", endpoint_login)] + ([("FTP", ftp_login)] if ftp_port else [])
if not ftp_port:
    c.info("the FTP daemon is not running or has no port: only the EndUser API is tried")

exists = admin.get("loginRestrictionPolicies", params={"name": POLICY}).json().get("result")
if exists or admin.exists("businessUnits/" + UNIT) or admin.exists("accounts/" + IN_UNIT) or admin.exists("accounts/" + OUTSIDE):
    c.check("no example_lre* policy, business unit or account exists yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

try:
    base = "/home/%s_%s" % (UNIT, RUN)
    c.check("set up: a business unit", admin.post("businessUnits", {"name": UNIT, "baseFolder": base}).status == 201)
    for uid, account, home, unit in (("1101", IN_UNIT, "%s/%s" % (base, IN_UNIT), UNIT), ("1102", OUTSIDE, "/home/%s" % OUTSIDE, None)):
        body = {"name": account, "type": "user", "uid": uid, "gid": uid, "homeFolder": home,
                "user": {"name": account, "passwordCredentials": {"password": PASSWORD}}}
        if unit:
            body["businessUnit"] = unit
        made = admin.post("accounts", body)
        c.check("set up: the account %s%s" % (account, " in the business unit" if unit else ", in no unit"), made.status == 201, made.text[:200])

    for label, how in protocols:
        c.check("before any policy, the account in the unit logs in over %s" % label, how(IN_UNIT) == "ok", how(IN_UNIT))
        c.check("before any policy, the account outside the unit logs in over %s" % label, how(OUTSIDE) == "ok", how(OUTSIDE))

    with runner.real_credentials(ADMIN_TREE, config):
        script("02.loginRestrictionPolicies_POST.sh", [POLICY, "DENY_THEN_ALLOW", "denies every address"])
        script("06.loginRestrictionPolicies_name_PATCH.sh", [POLICY, "deny all", "DENY", "*"])
        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [POLICY, UNIT])
        made = admin.get("loginRestrictionPolicies/" + POLICY).json()
        c.check("set up: the policy denies every address and is assigned to the unit, and only to it",
                (made["type"], [(r["type"], r["clientAddress"], r["isEnabled"]) for r in made["rules"]], made["businessUnits"], made["isDefault"])
                == ("DENY_THEN_ALLOW", [("DENY", "*", True)], [UNIT], False), made)

        for label, how in protocols:
            outcome = login_until(IN_UNIT, how, "refused")
            c.check("THE POLICY ENFORCES: the account in the unit is refused over %s" % label, outcome.startswith("refused"),
                    "%s; a DENY * policy is assigned to its business unit" % outcome)
            c.check("and the account outside the unit still logs in over %s" % label, how(OUTSIDE) == "ok", how(OUTSIDE))

        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [POLICY, UNIT, "remove"])
        for label, how in protocols:
            c.check("with the unit taken away, the account logs in again over %s" % label, login_until(IN_UNIT, how, "ok") == "ok", how(IN_UNIT))
finally:
    admin.delete("loginRestrictionPolicies/" + POLICY)
    for account in (IN_UNIT, OUTSIDE):
        admin.delete("accounts/" + account)
    admin.delete("businessUnits/" + UNIT)
    c.check("nothing is left behind: no policy, business unit or account",
            not admin.get("loginRestrictionPolicies", params={"name": POLICY}).json().get("result")
            and not admin.exists("businessUnits/" + UNIT) and not admin.exists("accounts/" + IN_UNIT) and not admin.exists("accounts/" + OUTSIDE))
    admin.logout()

sys.exit(c.done())
