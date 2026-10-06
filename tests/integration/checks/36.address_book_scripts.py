#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 19.AddressBook examples
against the server's LDAP address book source: lists, checks and reads it,
changes its page size (MaxPageEntries) with PATCH and then back with PUT, and
checks the whole source is exactly as it was.

An address book source is a server-wide setting: the API has no POST or
DELETE for them, so there is nothing throwaway to use. The page size is the
least consequential property there is, and this check restores the source's
exact original object in a finally block, whatever happens.

Skips when the server has no LDAP source. Needs --write and
st_allow_writes="yes".
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the address book examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Address book sources, run for real from Admin/API 2.0/bash/19.AddressBook")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "19.AddressBook")


def script(name, args=None):
    result = runner.run(os.path.join(FOLDER, name), args, timeout=60)
    out = result.stdout + result.stderr
    c.check("%s runs" % name, result.returncode == 0, out.strip()[-300:])
    return out


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /addressBook")
    admin.logout()
    sys.exit(c.done())

ldap = [s for s in (admin.get("addressBook/sources", params={"name": "LDAP"}).json() or {}).get("result", [])]
if not ldap:
    c.info("this server has no address book source named LDAP")
    admin.logout()
    sys.exit(c.done())
original = ldap[0]
SOURCE_PATH = "addressBook/sources/" + original["id"]
value = original.get("customProperties", {}).get("MaxPageEntries", "100")
changed = "97" if value != "97" else "96"

try:
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        out = script("01.addressBook_sources_GET.sh")
        c.check("01 lists the LDAP source", "%s  LDAP  LDAP" % original["id"] in out, out[-300:])
        out = script("02.addressBook_sources_id_HEAD.sh")
        c.check("02 finds it by name", "The source LDAP exists, id %s." % original["id"] in out, out[-200:])
        out = script("03.addressBook_sources_id_GET.sh")
        c.check("03 reads its custom properties", '"MaxPageEntries"' in out, out[-300:])

        out = script("05.addressBook_sources_id_PATCH.sh", [changed])
        now = admin.get(SOURCE_PATH).json() or {}
        c.check("05 PATCH set MaxPageEntries to %s, as a string" % changed,
                now.get("customProperties", {}).get("MaxPageEntries") == changed, now.get("customProperties"))
        c.check("05 printed the value before", "MaxPageEntries of LDAP is now %s." % value in out, out[-200:])

        script("04.addressBook_sources_id_PUT.sh", [value])
        c.check("04 PUT put it back, and the source is exactly as it was",
                admin.get(SOURCE_PATH).json() == original, admin.get(SOURCE_PATH).json())
finally:
    if admin.get(SOURCE_PATH).json() != original:
        admin.put(SOURCE_PATH, original)
    c.check("the source is exactly as it was", admin.get(SOURCE_PATH).json() == original)
    admin.logout()

sys.exit(c.done())
