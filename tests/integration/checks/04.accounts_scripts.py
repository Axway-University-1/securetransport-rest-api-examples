#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified scripts in
Admin/API 2.0/bash/05.Accounts against a configured server, in the order the
folder itself is numbered, and independently verifies every step through the
API - never by trusting the script's own exit code or stdout alone.

This is the check that closes the gap 01.connect.py / 02.read.py /
03.lifecycle.py leave open: those prove the API behaves as the examples
assume, using a client written for the harness. This one runs the files that
actually ship in this repository, so a bug in the curl invocation itself - bad
quoting, a stale field name, a broken jq filter - is what gets caught here.

Needs --write and st_allow_writes="yes", same as 03.lifecycle.py.

Known: this check reliably FAILS against --mock, on the very first script run,
with a 403. That is not a bug in the mock or in this check. None of the
05.Accounts scripts send a Referer header - confirmed true of 44 of the 45
Admin/API 2.0/bash examples - and the mock enforces Referer on every call,
matching the documented contract rather than any one lab's leniency. It has
been run clean against a real 5.5 server that happens not to enforce Referer
at all. See .claude/skills/st-api-gotchas/SKILL.md, "The Referer header is not
optional", for the full finding. Until the scripts send the header, --mock is
not useful for dry-running this specific check - use it against a real server.

Objects touched, by the literal names the scripts themselves use - these
scripts are not parameterised, so this is not a ZZTEST_ prefixed run:
    UserAccount, ServiceAccount, TemplateAccount   created by 02, deleted by 07
    john                                            see below

Safety:
  - Refuses to run at all if any of the three accounts above already exist,
    rather than risk colliding with or overwriting something already
    meaningful on the server. Fix that by hand before re-running this.
  - 06.accounts_name_PATCH.sh and its _with_file twin operate on a fixed
    account named "john" that this folder does not create and has no delete
    script for. If "john" does not exist, this check creates a minimal one,
    runs the real, unmodified scripts against it, and deletes it again
    afterward - never a pre-existing one.
  - If "john" already exists, this check does not skip outright: it creates a
    throwaway "john_test" account instead, and runs a copy of each 06 script
    with the account name substituted to match (script_runner.substituted_copy).
    That is not the same as running the real file - the same PATCH bodies and
    jq logic are exercised, under a name that does not collide, but it is a
    modified copy, and is reported as such rather than as the literal script.

Running that fallback against a genuinely fresh account (rather than the real
"john", which had already accumulated state from prior use) surfaced a real
bug in 06.accounts_name_PATCH.sh: its final PATCH added a contact at array
index 1, which only worked because "john" already had one contact at index 0.
Fixed to append with "-" instead, which works regardless of the array's
starting length - see .claude/skills/st-api-gotchas/SKILL.md, "Appending to an
array uses a dash", for the confirmed 400 this produced before the fix.
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
    st_client.skip("read only run, pass --write to run the accounts scripts for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Accounts, run for real from Admin/API 2.0/bash/05.Accounts")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
ACCOUNTS_DIR = os.path.join(BASH_TREE, "05.Accounts")
NAMES = ["UserAccount", "ServiceAccount", "TemplateAccount"]


def script(name):
    return os.path.join(ACCOUNTS_DIR, name)


def run_and_report(name, timeout=60):
    result = runner.run(script(name), timeout=timeout)
    ok = result.returncode == 0
    c.check("%s runs without a shell level error" % name, ok,
            result.stderr.strip()[-300:] if not ok else "")
    return result


client = st_client.connect(config, c)
created_john = False

try:
    with runner.real_credentials(BASH_TREE, config):

        # -- refuse to collide with anything already there ---------------------
        pre_existing = [n for n in NAMES if client.exists("accounts/" + n)]
        if pre_existing:
            c.check("none of %s already exist on this server" % NAMES, False, pre_existing)
            c.info("refusing to run 02.accounts_POST.sh: it would collide with "
                   "an account that is already there. Remove or rename %s on "
                   "the server, or point this at a cleaner lab, then try again."
                   % pre_existing)
            client.logout()
            sys.exit(c.done())
        c.check("none of %s already exist on this server" % NAMES, True)

        baseline = list(client.page("accounts"))
        c.info("%d accounts on the server before this run" % len(baseline))

        # -- 01: list accounts ---------------------------------------------------
        run_and_report("01.accounts_GET.sh")

        # -- 02: create the three accounts ---------------------------------------
        run_and_report("02.accounts_POST.sh")

        for n in NAMES:
            c.check("GET /accounts/%s now returns 200" % n,
                    client.get("accounts/" + n).status == 200)
        listed = {a.get("name") for a in client.page("accounts")}
        for n in NAMES:
            c.check("%s is listed in GET /accounts" % n, n in listed)

        # -- 03: HEAD check on UserAccount ---------------------------------------
        result = run_and_report("03.accounts_name_HEAD.sh")
        c.check("the script's own output reports the account exists",
                "Account Exists" in result.stdout
                and "Account does not exist" not in result.stdout,
                result.stdout[-200:])

        # -- 04: GET UserAccount several ways -------------------------------------
        run_and_report("04.accounts_name_GET.sh")
        # independently confirm the type specific field behaviour this script
        # demonstrates, using the account's own real data on this server
        without_type = client.get("accounts/UserAccount",
                                  params={"fields": "addressBookSettings"}).json() or {}
        with_type = client.get("accounts/UserAccount",
                               params={"type": "user",
                                       "fields": "addressBookSettings"}).json() or {}
        if "addressBookSettings" in with_type:
            c.check("a type specific field still needs type= on this server",
                    "addressBookSettings" not in without_type)
        else:
            c.info("this account has no addressBookSettings; the type= rule "
                   "could not be exercised here")

        # -- 05: PUT a new uid onto UserAccount -----------------------------------
        run_and_report("05.accounts_name_PUT.sh")
        after = client.get("accounts/UserAccount").json() or {}
        c.check("the uid set by the script is visible", str(after.get("uid")) == "1111",
                after.get("uid"))
        for leftover in ("result.json", "new_result.json"):
            c.check("05.accounts_name_PUT.sh does not leave %s behind" % leftover,
                    not os.path.exists(os.path.join(ACCOUNTS_DIR, leftover)))

        # -- 06: PATCH scripts, gated on an account named "john" -------------------
        target_account = "john"
        john_exists = client.exists("accounts/john")

        if john_exists:
            target_account = "john_test"
            c.info('an account named "john" already exists on this server; '
                   'using a throwaway "john_test" account and a name-substituted '
                   "copy of each 06 script instead of skipping outright - see "
                   "this check's own docstring for what that does and does not prove")
            if client.exists("accounts/" + target_account):
                c.info('"john_test" also already exists; skipping the substituted '
                       "run rather than risk touching that too")
                target_account = None

        if target_account:
            response = client.post("accounts", {
                "name": target_account, "type": "user", "uid": "1002", "gid": "1002",
                "homeFolder": "/home/" + target_account,
                "user": {"name": target_account, "passwordCredentials": {"password": "1"}},
            })
            created_john = response.status == 201
            c.check('created a throwaway "%s" account for these two scripts' % target_account,
                    created_john, response.text[:200])

            if created_john:
                subs = {} if not john_exists else {'ACCOUNT="john"': 'ACCOUNT="john_test"'}

                if john_exists:
                    with runner.substituted_copy(script("06.accounts_name_PATCH.sh"), subs) as copy:
                        run_and_report(os.path.basename(copy))
                else:
                    run_and_report("06.accounts_name_PATCH.sh")

                target = client.get("accounts/" + target_account,
                                    params={"type": "user"}).json() or {}
                abs_ = target.get("addressBookSettings") or {}
                contacts = abs_.get("contacts", [])
                label = "06.accounts_name_PATCH.sh" + (" (name-substituted copy)" if john_exists else "")
                c.check("the new contact from %s is present" % label,
                        any(x.get("fullName") == "Jane Doe" for x in contacts), contacts)
                # A "remove" here does not drop the key from the object - confirmed
                # directly: addressBookSettings always carries this field, null when
                # unset. "remove" resets it to that same null, so its presence is
                # not itself informative; whether it is null is.
                c.check("nonAddressBookCollaborationAllowed was reset to null by remove",
                        abs_.get("nonAddressBookCollaborationAllowed") is None, abs_)
                if john_exists:
                    c.info("the script's first PATCH call (policy=\"custom\") is expected "
                           "to 400 against a synthetic account here - confirmed directly: "
                           "the server requires addressBookSettings.sources to already "
                           'have at least two entries before "custom" is accepted, which '
                           'only an LDAP-integrated account like the real "john" has by '
                           "default. The script does not check that call's response code, "
                           "so this does not surface as a shell level error, and the PATCH "
                           "right after it overwrites policy back to \"default\" regardless.")

                if john_exists:
                    with runner.substituted_copy(
                            script("06.accounts_name_PATCH_with_file.sh"), subs) as copy:
                        run_and_report(os.path.basename(copy))
                else:
                    run_and_report("06.accounts_name_PATCH_with_file.sh")

                target = client.get("accounts/" + target_account,
                                    params={"type": "user"}).json() or {}
                contacts = (target.get("addressBookSettings") or {}).get("contacts", [])
                label = ("06.accounts_name_PATCH_with_file.sh" +
                        (" (name-substituted copy)" if john_exists else ""))
                c.check("the contact from stPatchAccount.json is present via %s" % label,
                        any(x.get("fullName") == "Test 2Contact421" for x in contacts),
                        contacts)

                if john_exists:
                    client.delete("accounts/" + target_account)
                    c.check('the throwaway "%s" account was removed' % target_account,
                            not client.exists("accounts/" + target_account))
                    created_john = False  # already cleaned up here, not in the finally below

        # -- 07: delete the three accounts ---------------------------------------
        run_and_report("07.accounts_name_DELETE.sh")
        for n in NAMES:
            c.check("%s is gone after 07.accounts_name_DELETE.sh" % n,
                    not client.exists("accounts/" + n))

finally:
    # Clean up the throwaway john ourselves, only if we created it. Never
    # remove one that already existed on the server before this run.
    if created_john:
        client.delete("accounts/john")
        c.check('the throwaway "john" account was removed', not client.exists("accounts/john"))
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
