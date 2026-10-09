#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Checks that a login restriction policy does what it says:
a policy that denies every address, assigned to a business unit, stops the
accounts of that unit logging in, and only them.

SFTP and HTTP (the EndUser API) are the CORE protocols, run first; FTP is legacy and
is an additional, labelled part ("FTP (legacy): ..."). The same steps for each:

  1. Two throwaway end user accounts: one in a throwaway business unit, one in
     none. Both log in before any policy.
  2. The real 26.LoginRestrictionPolicies examples create the policy
     (DENY_THEN_ALLOW), add the rule that denies every address, and assign the
     policy to the business unit (once, for all the protocols).
  3. The account in the unit must now be REFUSED, and the account outside it must
     still get in.
  4. The real example takes the unit away again, and the first account logs in.

THIS CHECK FAILS, BY DESIGN, ON THE LAB THE EXAMPLES WERE WRITTEN AGAINST. There,
step 3 does not hold, for any of the three protocols (measured 2026-10-08 on
5.5-20260924, policy type DENY_THEN_ALLOW, one rule DENY *, assigned to the unit):
  - SFTP (the system sftp client, a login proved by answering `pwd`): the account of
    the unit is NOT refused. It keeps logging in, on every try for the 20 seconds the
    check waits (8 tries over 21 seconds, every one `ok`).
  - HTTP (an EndUser API login, POST /myself): NOT refused either; the answer is 200
    on every try (8 tries over 20 seconds).
  - FTP (ftplib): NOT refused; 230 on every try (10 tries over 21 seconds).
Earlier probes of FTP and HTTP waited two minutes, with either policy type, and saw the same
(SFTP was not waited on that long). The account
outside the unit gets in over all three (as it must), and with the unit taken away the
account of the unit logs in over all three. So the lab's failures are exactly three:
"SFTP: THE POLICY ENFORCES ...", "HTTP: THE POLICY ENFORCES ..." and "FTP (legacy): THE
POLICY ENFORCES ...", and nothing else. The wait per protocol is capped at 20 seconds, so
the whole failing run takes about 80 seconds. The check is here so that this is not
forgotten: it fails until enforcement works, and then it passes by itself.
45.login_restriction_policies_scripts.py covers the API and stays green. Whatever makes a
policy take effect on a server (a setting, a restart) belongs in this check's set up, once
it is known. The assertions are never weakened or skipped for a protocol that does not
enforce: that is the finding.

SFTP needs the SSH daemon and an `sftp` client on this machine; FTP needs the FTP daemon
(a missing one is only mentioned). Needs --write and st_allow_writes="yes". Refuses to
start when its example_lre* objects exist, and removes everything in a finally block,
whatever the assertions found: no policy, unit or account is left. No policy is ever made
the default.
"""
import contextlib
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402
import protocol_logins  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the login restriction enforcement check for real")

c = st_client.Checker("Login restriction policy enforcement, run for real with 26.LoginRestrictionPolicies")
ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
FOLDER = os.path.join(ADMIN_TREE, "26.LoginRestrictionPolicies")
POLICY, UNIT = "example_lre", "example_lre_bu"
IN_UNIT, OUTSIDE = "example_lre_user", "example_lre_other"
RUN = harness.suffix(8)
IN_UNIT, OUTSIDE = IN_UNIT + "_" + RUN, OUTSIDE + "_" + RUN
PASSWORD = harness.new_password()
ENDUSER_PORT = harness.ports(config).enduser
HOST = config["st_server"]
WAIT_SECONDS = 20


script = harness.bind_script(c, FOLDER, timeout=90)


def login_until(account, proto, wanted, seconds=WAIT_SECONDS):
    """(the outcome, the tries made, the seconds spent): the login is tried again every 2 seconds until its outcome
    starts with `wanted` ('ok' or 'refused') or `seconds` have passed (the cap per protocol)."""
    start = time.time()
    tries, last = [0], [None]

    def attempt():
        last[0] = logins.try_login(proto, account)
        tries[0] += 1
        return last[0].startswith(wanted)
    harness.wait_until(attempt, seconds, 2)
    return last[0], tries[0], int(time.time() - start)


admin = harness.connect(config, c, mock="the bundled mock does not implement /loginRestrictionPolicies or the protocol servers")

ports = harness.ports(config, admin)
daemons = admin.get("daemons").json()
ftp_port = ports.ftp if daemons.get("ftpStatus") == "Running" else None
ssh_port = ports.ssh if daemons.get("sshStatus") == "Running" else None
if not ssh_port or not shutil.which("sftp"):
    c.check("SFTP, a core protocol, can be exercised", False, "the SSH daemon is not running, or there is no sftp client on this machine")
    admin.logout()
    sys.exit(c.done())
logins = protocol_logins.Logins(HOST, ssh_port, ENDUSER_PORT, ftp_port, PASSWORD)
LABELS = {"SFTP": "SFTP", "HTTP": "HTTP", "FTP": "FTP (legacy)"}
protocols = ["SFTP", "HTTP"] + (["FTP"] if ftp_port else [])
if not ftp_port:
    c.info("the FTP daemon is not running or has no port: the legacy FTP part is left out")

exists = admin.get("loginRestrictionPolicies", params={"name": POLICY}).json().get("result")
if exists or admin.exists("businessUnits/" + UNIT):
    c.check("no example_lre* policy or business unit exists yet", False, "remove them first; this check will not touch them")
    logins.cleanup()
    admin.logout()
    sys.exit(c.done())

accounts = contextlib.ExitStack()
try:
    base = "/home/%s_%s" % (UNIT, RUN)
    c.check("set up: a business unit", admin.post("businessUnits", {"name": UNIT, "baseFolder": base}).status == 201)
    for account, home, unit in ((IN_UNIT, "%s/%s" % (base, IN_UNIT), UNIT), (OUTSIDE, "/home/%s" % OUTSIDE, None)):
        accounts.enter_context(harness.throwaway_account(
            admin, c, config, name=account, password=PASSWORD, home=home, extra={"businessUnit": unit} if unit else None,
            label="set up: the account %s%s" % (account, " in the business unit" if unit else ", in no unit")))

    for proto in protocols:
        label = LABELS[proto]
        got = logins.try_login(proto, IN_UNIT)
        c.check("%s: before any policy, the account in the unit logs in" % label, got == "ok", got)
        got = logins.try_login(proto, OUTSIDE)
        c.check("%s: before any policy, the account outside the unit logs in" % label, got == "ok", got)

    with runner.real_credentials(ADMIN_TREE, config):
        script("02.loginRestrictionPolicies_POST.sh", [POLICY, "DENY_THEN_ALLOW", "denies every address"])
        script("06.loginRestrictionPolicies_name_PATCH.sh", [POLICY, "deny all", "DENY", "*"])
        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [POLICY, UNIT])
        made = admin.get("loginRestrictionPolicies/" + POLICY).json()
        c.check("set up: the policy denies every address and is assigned to the unit, and only to it",
                (made["type"], [(r["type"], r["clientAddress"], r["isEnabled"]) for r in made["rules"]], made["businessUnits"], made["isDefault"])
                == ("DENY_THEN_ALLOW", [("DENY", "*", True)], [UNIT], False), made)

        for proto in protocols:
            label = LABELS[proto]
            outcome, tries, spent = login_until(IN_UNIT, proto, "refused")
            c.info("%s: the account in the unit was %s after %d tries over %d seconds" % (label, outcome, tries, spent))
            c.check("%s: THE POLICY ENFORCES: the account in the unit is refused" % label, outcome.startswith("refused"),
                    "%s after %d tries over %d seconds; a DENY * policy is assigned to its business unit" % (outcome, tries, spent))
            got = logins.try_login(proto, OUTSIDE)
            c.check("%s: and the account outside the unit still logs in" % label, got == "ok", got)

        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [POLICY, UNIT, "remove"])
        for proto in protocols:
            outcome, tries, spent = login_until(IN_UNIT, proto, "ok")
            c.check("%s: with the unit taken away, the account logs in again" % LABELS[proto], outcome == "ok", outcome)
finally:
    logins.cleanup()
    admin.delete("loginRestrictionPolicies/" + POLICY)
    accounts.close()
    admin.delete("businessUnits/" + UNIT)
    c.check("nothing is left behind: no policy, business unit or account",
            not admin.get("loginRestrictionPolicies", params={"name": POLICY}).json().get("result")
            and not admin.exists("businessUnits/" + UNIT) and not admin.exists("accounts/" + IN_UNIT) and not admin.exists("accounts/" + OUTSIDE))
    admin.logout()

sys.exit(c.done())
