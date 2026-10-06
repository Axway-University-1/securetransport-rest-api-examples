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
import base64
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the account setup examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Account setup, run for real from Admin/API 2.0/bash/18.AccountSetup")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "18.AccountSetup")
ACCOUNT = "example_setup"
os.environ["ACCOUNT_PASSWORD"] = "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"


def script(name, args=None):
    result = runner.run(os.path.join(FOLDER, name), args, timeout=60)
    out = result.stdout + result.stderr
    c.check("%s runs" % name, result.returncode == 0, out.strip()[-300:])
    return out


def sites():
    return sorted(s.get("name") for s in (admin.get("sites", params={"account": ACCOUNT}).json() or {}).get("result", []))


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /accountSetup")
    admin.logout()
    sys.exit(c.done())

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
