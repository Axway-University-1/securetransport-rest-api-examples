#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 17.AccessPolicies examples:
adds a database access policy (a pg_hba.conf rule), checks, reads and replaces
it, adds a second copy, and deletes both - then checks the server's own rules
are exactly as they were.

The rule the examples add rejects connections to a database named example_db,
as example_user, from the server itself. No such database exists, and the
rule is added after the server's own rules, so it changes no real connection.

Confirmed directly while writing the examples: a rule's id is its line in the
file, and the ids after a deleted rule move up. The delete example lists the
rules again before each delete; deleting ids found in one listing would, from
the second one on, delete the wrong rules - a real danger here, where a wrong
delete can lock SecureTransport out of its own database.

Skips on a server whose database is not the embedded PostgreSQL. Refuses to
run if an example_db rule is already there. Needs --write and
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
    st_client.skip("read only run, pass --write to run the access policy examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Access policies, run for real from Admin/API 2.0/bash/17.AccessPolicies")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "17.AccessPolicies")


def rules():
    return admin.get("accessPolicies").json() or []


def mine():
    return [p for p in rules() if p.get("database") == "example_db" and p.get("user") == "example_user"]


def script(name, args=None):
    result = runner.run(os.path.join(FOLDER, name), args, timeout=60)
    out = result.stdout + result.stderr
    c.check("%s runs" % name, result.returncode == 0, out.strip()[-300:])
    return out


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /accessPolicies")
    admin.logout()
    sys.exit(c.done())

response = admin.get("accessPolicies")
if response.status != 200 or not isinstance(response.json(), list):
    c.info("no access policies here (HTTP %s): not the embedded PostgreSQL database" % response.status)
    admin.logout()
    sys.exit(c.done())

before = rules()
c.check("no example_db rule is there yet", not mine(), mine())
if mine():
    admin.logout()
    sys.exit(c.done())

try:
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        out = script("02.accessPolicies_POST.sh")
        added = mine()
        c.check("02 added one rule, after the server's own", len(added) == 1 and added[0]["id"] == len(before) + 1, added)
        c.check("02 printed its id", "The new rule is number %d." % (len(before) + 1) in out, out[-200:])
        c.check("the server's own rules are unchanged", rules()[:len(before)] == before)

        out = script("01.accessPolicies_GET.sh")
        c.check("01 lists it", "example_db  example_user  samehost  reject" in out, out[-300:])
        out = script("03.accessPolicies_id_HEAD.sh")
        c.check("03 finds it", "Rule %d exists." % (len(before) + 1) in out, out[-200:])
        out = script("04.accessPolicies_id_GET.sh")
        c.check("04 reads it", '"authMethod" : "reject"' in out, out[-300:])

        script("05.accessPolicies_id_PUT.sh", ["md5"])
        c.check("05 changed its method, and only that", [(p["database"], p["authMethod"]) for p in mine()] == [("example_db", "md5")], mine())

        script("02.accessPolicies_POST.sh")
        c.check("a second copy is allowed", len(mine()) == 2, mine())
        out = script("06.accessPolicies_id_DELETE.sh")
        c.check("06 deleted both, the last first", "Deleting rule %d" % (len(before) + 2) in out
                and "Deleted 2 rule(s)" in out, out[-300:])
finally:
    # Whatever is left, deleted the same safe way: list again, delete the last match
    while mine():
        admin.delete("accessPolicies/%s" % mine()[-1]["id"])
    c.check("the server's rules are exactly as they were", rules() == before, rules())
    admin.logout()

sys.exit(c.done())
