#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs three End User examples that need something the lab does not have (a mailbox, an AS2
transfer) for what they can show without it: how the server answers them, and that the script says so and exits
accordingly. Uses a throwaway account with an e-mail address this check creates and removes.

  - 04 requestLink: the server answers 200, for the account's own address and for an address it does not know alike
    (it does not tell which exists); the script exits 0 and prints the HTTP status. The mail itself is not checked:
    the lab sends none.
  - 05 reset with a token that was never issued: refused 401 "Invalid token", and the script exits 1 (it used to
    print the refusal and exit 0, so a caller could not tell).
  - 07 verifymdn for a transfer id that does not exist: refused, exit 1, and the answer is shown.

Not confirmed here, and said so in the notes of 04, 05 and 07: the mail, a real token, a real AS2 receipt.

Needs --write and st_allow_writes="yes".
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "ask for a password reset and a receipt check for a throwaway account")

c = st_client.Checker("EndUser password recovery (04, 05) and receipt check (07), as far as the lab goes")

TREE = runner.path("EndUser", "API 2.0", "bash")
ENDUSER_PORT = harness.ports(config).enduser

admin = harness.connect(config, c, mock=("the bundled mock does not implement the EndUser API on a second port; "
                                         "run this against a real server to exercise it"))
try:
    with harness.throwaway_account(admin, c, config, prefix="ZZTEST_eu_rec", extra={"contact": {"email": "zztest_eu_rec@example.com"}}) as acct:
        def run(script, args, user=None, password=None):
            cfg = dict(config, st_port=ENDUSER_PORT, st_user=user or acct.name, st_password=password or acct.password)
            with runner.real_credentials(TREE, cfg):
                return runner.run(os.path.join(TREE, script), args, timeout=120)

        r = run("03.Myself/04.myself_password_POST_requestLink.sh", ["zztest_eu_rec@example.com"])
        c.check("04 for the account's own address: exit 0 and the server's 200", r.returncode == 0 and "HTTP 200" in r.stdout, (r.returncode, r.stdout[-200:]))
        r = run("03.Myself/04.myself_password_POST_requestLink.sh", ["nobody_zz@example.com"], user="nobody_zz")
        c.check("04 for an address nobody has: the same 200 (the server does not say which exist)", r.returncode == 0 and "HTTP 200" in r.stdout, (r.returncode, r.stdout[-200:]))

        r = run("03.Myself/05.myself_password_POST_reset.sh", ["token-never-issued", harness.new_password()])
        c.check("05 with a token that was never issued: the server's refusal is shown (401, Invalid token)",
                "HTTP 401" in r.stdout and "error.token.invalid" in r.stdout, r.stdout[-300:])
        c.check("and the script exits 1, not 0", r.returncode == 1, r.returncode)
        # the account still logs in with its own password: nothing was reset
        client = st_client.EndUserClient(config["st_server"], ENDUSER_PORT, acct.name, acct.password)
        c.check("and the account's password is unchanged", client.login_response().status == 200)
        client.logout()

        r = run("05.Transfers/07.transfers_id_operations_POST_verifymdn.sh", ["no-such-transfer-zz"])
        c.check("07 for a transfer that does not exist: exit 1, and the server's answer is shown",
                r.returncode == 1 and "HTTP" in r.stdout, (r.returncode, r.stdout[-300:]))
finally:
    admin.logout()
sys.exit(c.done())
