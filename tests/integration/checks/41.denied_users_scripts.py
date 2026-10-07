#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 22.DeniedUsers examples:
blocks a login name for good, and one with a space for two hours, lists them
with each filter, shows a duplicate and bad arguments refused, and unblocks
them, checking each effect through the API. A name that differs only in case is
blocked through the API, to show that removing one leaves the other.

It also shows what a block is for: two throwaway end user accounts are created,
both log in through the EndUser API, then 02.deniedUsers_POST.sh blocks one of
them. The blocked one is refused at login (401), the other still gets in, and
once 03.deniedUsers_name_DELETE.sh unblocks the first, it logs in again.

Needs --write and st_allow_writes="yes". Refuses to start when any login name
starting with "example" is already denied, and removes what it adds in a
finally block. It never touches an entry it did not add, and ends by comparing
the whole list with the one it started with.
"""
import base64
import os
import sys
from urllib.parse import quote

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the denied users examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Denied users, run for real from Admin/API 2.0/bash/22.DeniedUsers")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "22.DeniedUsers")
PERMANENT, TEMPORARY, UPPER = "example_denied", "example denied space", "EXAMPLE_DENIED"
OURS = (PERMANENT, TEMPORARY, UPPER)
BLOCKED_ACCOUNT, OTHER_ACCOUNT = "example_blocked_user", "example_allowed_user"
ACCOUNT_PASSWORD = "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"
ENDUSER_PORT = config.get("st_enduser_port") or str(int(config["st_port"]) - 1)


def script(name, args=None, expect_rc=0):
    result = runner.run(os.path.join(FOLDER, name), args, timeout=60)
    out = result.stdout + result.stderr
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc, out.strip()[-300:])
    return out


def listing(pattern="*"):
    return (admin.get("deniedUsers", params={"loginName": pattern, "limit": 500}).json() or {}).get("result", [])


def end_user_login(account):
    """The HTTP status of an EndUser login as this account, logging out again after a success."""
    client = st_client.EndUserClient(config["st_server"], ENDUSER_PORT, account, ACCOUNT_PASSWORD)
    response = client._request("POST", "myself", headers={"Authorization": "Basic " + client._auth})
    if response.status == 200:
        client.logout()
    return response


def entry(name):
    return [e for e in listing(name) if e["loginName"] == name]


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /deniedUsers or the EndUser login")
    admin.logout()
    sys.exit(c.done())
if any(e["loginName"].lower().startswith("example") for e in listing()):
    c.check("no denied login name starts with example yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

if admin.exists("accounts/" + BLOCKED_ACCOUNT) or admin.exists("accounts/" + OTHER_ACCOUNT):
    c.check("the accounts %s and %s do not exist yet" % (BLOCKED_ACCOUNT, OTHER_ACCOUNT), False,
            "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

before = sorted(e["loginName"] for e in listing())
try:
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        out = script("02.deniedUsers_POST.sh")
        e = entry(PERMANENT)
        c.check("02 blocked example_denied for good", len(e) == 1 and e[0]["blockedUntil"] is None, e)
        c.check("02 printed the entry's address, from Location", "It is at" in out and "/deniedUsers/%s" % PERMANENT in out, out[-200:])

        out = script("02.deniedUsers_POST.sh", [TEMPORARY, "2", "two hours"])
        e = entry(TEMPORARY)
        c.check("02 blocked a name with a space for two hours, with its note",
                len(e) == 1 and e[0]["blockedUntil"] is not None and e[0]["note"] == "two hours", e)

        script("02.deniedUsers_POST.sh", expect_rc=1)
        c.check("02 a name already blocked is refused, and still listed once", len(entry(PERMANENT)) == 1)
        total = len(listing())
        script("02.deniedUsers_POST.sh", [" "], expect_rc=2)
        script("02.deniedUsers_POST.sh", ["example_zero", "0"], expect_rc=2)
        script("02.deniedUsers_POST.sh", ["example_neg", "-1"], expect_rc=2)
        c.check("02 a blank name and a 0 or negative number of hours sent nothing",
                len(listing()) == total and not entry("example_zero") and not entry("example_neg"))

        out = script("01.deniedUsers_GET.sh", ["example*", "2000-01-01"])
        sections = {part.split(":\n", 1)[0]: part.split(":\n", 1)[1] if ":\n" in part else "" for part in out.split("\n\n")}
        permanent = next((v for k, v in sections.items() if k.startswith("Only the permanent")), "")
        temporary = next((v for k, v in sections.items() if k.startswith("Only the temporary")), "")
        since = next((v for k, v in sections.items() if k.startswith("Blocked on or after")), "")
        c.check("01 lists both, by pattern", ("  %s  permanent  by" % PERMANENT) in out and ("  %s  until" % TEMPORARY) in out, out[-400:])
        c.check("01 the permanent ones are only the permanent one",
                PERMANENT in permanent and TEMPORARY not in permanent, permanent)
        c.check("01 the temporary ones are only the temporary one",
                TEMPORARY in temporary and PERMANENT not in temporary, temporary)
        c.check("01 the since filter lists both, as both were blocked just now", PERMANENT in since and TEMPORARY in since, since)
        out = script("01.deniedUsers_GET.sh", ["example*", "2999-01-01"])
        c.check("01 a date in the future lists none", "  %s  " % PERMANENT not in out.split("Blocked on or after")[-1], out[-200:])
        script("01.deniedUsers_GET.sh", ["*", "yesterday"], expect_rc=2)
        out = script("01.deniedUsers_GET.sh")
        c.check("01 the count is the number of entries", out.startswith("Denied users: %d\n" % len(listing())), out[:60])

        # A name that differs in case is another entry; the filter ignores case
        c.check("a name differing only in case can be blocked too", admin.post("deniedUsers", {"loginName": UPPER}).status == 201)
        c.check("the loginName filter does not tell them apart, there are 2 for example_denied",
                len([x for x in listing(PERMANENT)]) == 2)
        script("03.deniedUsers_name_DELETE.sh", [PERMANENT])
        c.check("03 deleted example_denied and left EXAMPLE_DENIED", not entry(PERMANENT) and len(entry(UPPER)) == 1)
        out = script("03.deniedUsers_name_DELETE.sh", [PERMANENT], expect_rc=1)
        c.check("03 a name not in the list is refused, with the server's reason", "No denied user found" in out, out[-200:])
        script("03.deniedUsers_name_DELETE.sh", [TEMPORARY])
        c.check("03 deleted the name with a space", not entry(TEMPORARY))
        script("03.deniedUsers_name_DELETE.sh", [" "], expect_rc=2)

        # --- what a block is for: one account blocked, one not, both logging in
        for uid, account in (("1061", BLOCKED_ACCOUNT), ("1062", OTHER_ACCOUNT)):
            made = admin.post("accounts", {"name": account, "type": "user", "uid": uid, "gid": uid,
                                           "homeFolder": "/home/" + account,
                                           "user": {"name": account, "passwordCredentials": {"password": ACCOUNT_PASSWORD}}})
            c.check("created the account %s" % account, made.status == 201, made.text[:200])
        c.check("before any block, the first account logs in", end_user_login(BLOCKED_ACCOUNT).status == 200)
        c.check("before any block, the second account logs in", end_user_login(OTHER_ACCOUNT).status == 200)

        script("02.deniedUsers_POST.sh", [BLOCKED_ACCOUNT, "1", "login test"])
        c.check("the first account is in the denied users", len(entry(BLOCKED_ACCOUNT)) == 1)
        refused = end_user_login(BLOCKED_ACCOUNT)
        c.check("the blocked account cannot log in: 401, Login failed",
                refused.status == 401 and "Login failed" in refused.text, (refused.status, refused.text[:120]))
        c.check("the other account, not in the list, still logs in", end_user_login(OTHER_ACCOUNT).status == 200)

        script("03.deniedUsers_name_DELETE.sh", [BLOCKED_ACCOUNT])
        c.check("once unblocked, the first account logs in again", end_user_login(BLOCKED_ACCOUNT).status == 200)
finally:
    for name in OURS + (BLOCKED_ACCOUNT,):
        if entry(name):
            admin.delete("deniedUsers/" + quote(name, safe=""))
    for account in (BLOCKED_ACCOUNT, OTHER_ACCOUNT):
        if admin.exists("accounts/" + account):
            admin.delete("accounts/" + account)
    c.check("the list is exactly as it was before", sorted(e["loginName"] for e in listing()) == before,
            sorted(set(e["loginName"] for e in listing()) ^ set(before)))
    c.check("both accounts are gone", not admin.exists("accounts/" + BLOCKED_ACCOUNT)
            and not admin.exists("accounts/" + OTHER_ACCOUNT))
    admin.logout()

sys.exit(c.done())
