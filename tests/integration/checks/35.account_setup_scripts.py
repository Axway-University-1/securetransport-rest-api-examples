#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 18.AccountSetup examples:
sets up the account example_setup and an SSH site in one call, adds a second
site to the existing account the same way, reads the whole setup back, and
deletes the account - checking each step through the API, and that the
account's sites go with it.

Confirmed directly while writing them: /accountSetup is not all or nothing (a
body that fails part of the way leaves what came before it created), an
existing account is skipped rather than refused, and deleting the account
deletes its sites and transfer profiles.

Refuses to run if example_setup already exists. Needs --write and
st_allow_writes="yes".
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the account setup examples for real")

c = st_client.Checker("Account setup, run for real from Admin/API 2.0/bash/18.AccountSetup")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "18.AccountSetup")
ACCOUNT = "example_setup"
os.environ["ACCOUNT_PASSWORD"] = harness.new_password()


script = harness.bind_script(c, FOLDER, timeout=60, label="{name} runs")


def sites():
    return sorted(s.get("name") for s in (admin.get("sites", params={"account": ACCOUNT}).json() or {}).get("result", []))


admin = harness.connect(config, c, mock="the bundled mock does not implement /accountSetup")

c.check("%s does not exist yet" % ACCOUNT, not admin.exists("accounts/" + ACCOUNT))
if admin.exists("accounts/" + ACCOUNT):
    admin.logout()
    sys.exit(c.done())

try:
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        out = script("01.accountSetup_POST.sh")
        c.check("01 created the account and its site", admin.exists("accounts/" + ACCOUNT)
                and sites() == ["example_setup_site"], sites())
        c.check("01 printed a message per object", "Account with name example_setup created." in out, out[-300:])

        out = script("03.accountSetup_POST_existing.sh")
        c.check("03 skipped the account and added the second site", "skipped because it already exists" in out
                and sites() == ["example_setup_site", "example_setup_site2"], (sites(), out[-300:]))

        out = script("02.accountSetup_name_GET.sh")
        c.check("02 read the whole setup", "sites              " in out and "example_setup_site" in out, out[-400:])

        script("04.accounts_name_DELETE.sh")
        c.check("04 deleted the account", not admin.exists("accounts/" + ACCOUNT))
        c.check("and its sites with it", sites() == [], sites())
finally:
    if admin.exists("accounts/" + ACCOUNT):
        admin.delete("accounts/" + ACCOUNT)
    c.check("nothing is left", not admin.exists("accounts/" + ACCOUNT) and sites() == [])
    os.environ.pop("ACCOUNT_PASSWORD", None)
    admin.logout()

sys.exit(c.done())
