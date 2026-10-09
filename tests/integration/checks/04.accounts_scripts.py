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

The scripts act on harmless objects of their own, so nothing here is a
substituted copy and no real account is touched:
    example_user, example_service, example_template   created by 02, deleted by 07
    every other account                              left alone: the check keeps the
                                                     list of accounts and, when there is
                                                     one, the whole of "john", and compares
                                                     them again at the end

It refuses to run at all if one of the three accounts already exists, rather
than risk colliding with something already meaningful on the server.

What it runs, and what it expects:
    02  refused with exit 2 for too many arguments (nothing created); then creates the three
        accounts, with a generated password (printed, 16 characters) and again, after 07, with
        one from the environment (never printed); a second run is refused (409), exit 1. The
        template account is put in the first user class that is not real, by order, which the
        check reads from /userClasses itself
    03  exit 0 and "Account Exists"; exit 1 for an account that is not there
    04  exit 0 (its third call is refused by the server, and that is the demonstration)
    05  the uid becomes 1111, the script says how to put it back, and that command puts it back
    06  the address book settings change as the script says, and the two bodies it prints
        put them back and take the contact out again
    06 with a file  the sample bodies, and refusals for a missing or a bad file; the sample
        that moves the account into the business unit "Pippin" is refused where there is none
    07  deletes the three, then says they do not exist; refuses an empty name

Known, found by this check: it used to FAIL against --mock, for two reasons nobody had
named. The first was in the scripts: 03 and 07 read the HTTP status with
"curl ... 2>&1 | grep HTTP | awk", and the mock answers with a header "Server:
BaseHTTP/0.6 Python/3.14.4" that also contains HTTP, so the status came out as two words
and was never "200" (the scripts now read it with curl -w). The second was in the mock: it
read the JSON Patch path "/addressBookSettings/contacts/-" as a top level field with
that name, so the contacts that 06 adds never arrived. Both are fixed.
"""
import contextlib
import json
import os
import re
import secrets
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the accounts scripts for real")

c = st_client.Checker("Accounts, run for real from Admin/API 2.0/bash/05.Accounts")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
ACCOUNTS_DIR = os.path.join(BASH_TREE, "05.Accounts")
BODY_DIR = os.path.join(ACCOUNTS_DIR, "06.patch_body")
USER, SERVICE, TEMPLATE = "example_user", "example_service", "example_template"
NAMES = [USER, SERVICE, TEMPLATE]


@contextlib.contextmanager
def environment(**values):
    """Put values in the environment of the scripts (they read ACCOUNT_PASSWORD from it), and take them out again."""
    previous = {k: os.environ.get(k) for k in values}
    os.environ.update({k: v for k, v in values.items() if v is not None})
    for k, v in values.items():
        if v is None:
            os.environ.pop(k, None)
    try:
        yield
    finally:
        for k, v in previous.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def run(name, args=None, expect_rc=0, timeout=60):
    """Run a script, check its exit code, and give back its output."""
    return harness.run_script(c, ACCOUNTS_DIR, name, args, expect_rc, timeout=timeout)


client = st_client.connect(config, c)
mock = st_client.is_mock(client)


def account(name, **params):
    return client.get("accounts/" + name, params=params or None).json() or {}


baseline_names = None
john_before = None
try:
    with runner.real_credentials(BASH_TREE, config):

        # -- refuse to collide with anything already there ---------------------
        pre_existing = [n for n in NAMES if client.exists("accounts/" + n)]
        if pre_existing:
            c.check("none of %s already exist on this server" % NAMES, False, pre_existing)
            c.info("refusing to run 02.accounts_POST.sh: it would collide with an account that is already there. "
                   "Remove or rename %s on the server, or point this at a cleaner lab, then try again." % pre_existing)
            client.logout()
            sys.exit(c.done())
        c.check("none of %s already exist on this server" % NAMES, True)

        baseline_names = sorted(a.get("name") for a in client.page("accounts"))
        c.info("%d accounts on the server before this run" % len(baseline_names))
        john_before = account("john") if client.exists("accounts/john") else None
        if john_before:
            c.info('an account named "john" exists: it is not touched, and is compared again at the end')

        # The class the template account must get: the first one that is not real, by order. The
        # bundled mock has no /userClasses, so there the class is given to the script.
        template_class_args = []
        expected_class = "VirtClass"
        if mock:
            template_class_args = [expected_class]
        else:
            classes = client.get("userClasses", params={"fields": "className,userType,order"}).json() or {}
            usable = sorted((x for x in classes.get("result", []) if x.get("userType") != "real"), key=lambda x: x.get("order", 0))
            c.check("the server has a user class that is not real, to put the template account in", bool(usable), classes)
            expected_class = usable[0]["className"] if usable else None

        # -- 01: list accounts ---------------------------------------------------
        run("01.accounts_GET.sh")

        # -- 02: too many arguments is refused before anything is sent ----------------
        out = run("02.accounts_POST.sh", ["a", "b"], expect_rc=2)
        c.check("02 with too many arguments created nothing", not any(client.exists("accounts/" + n) for n in NAMES))

        # -- 02: create the three accounts, with a generated password -----------------
        with environment(ACCOUNT_PASSWORD=None):
            out = run("02.accounts_POST.sh", template_class_args)
        shown = re.search(r"The password of %s is (\S+) \(generated" % USER, out)
        c.check("a generated password is printed once, 16 characters", bool(shown) and len(shown.group(1)) == 16, out[-200:])
        c.check("each creation prints HTTP 201", out.count("HTTP 201") == 3, out[-300:])
        for n in NAMES:
            c.check("GET /accounts/%s now returns 200" % n, client.get("accounts/" + n).status == 200)
        listed = {a.get("name") for a in client.page("accounts")}
        for n in NAMES:
            c.check("%s is listed in GET /accounts" % n, n in listed)
        user = account(USER)
        c.check("example_user has the home folder and the fixed uid", (user.get("homeFolder"), str(user.get("uid"))) == ("/home/" + USER, "41733"), user.get("homeFolder"))
        template = account(TEMPLATE, type="template", fields="type,templateClass")
        c.check("the template account is in a class the script looked up (%s)" % expected_class,
                template.get("templateClass") == expected_class, template)

        # a second run is refused by the server (409), and the script says so with its exit code
        out = run("02.accounts_POST.sh", template_class_args, expect_rc=1)
        c.check("the refusal of a duplicate shows its HTTP code", out.count("HTTP 409") == 3, out[-300:])

        # -- 07 (now), then 02 again with a password from the environment ------------
        run("07.accounts_name_DELETE.sh")
        for n in NAMES:
            c.check("%s is gone after 07" % n, not client.exists("accounts/" + n))
        password = "Zz1!" + secrets.token_hex(6)
        with environment(ACCOUNT_PASSWORD=password):
            out = run("02.accounts_POST.sh", template_class_args)
        c.check("a password from the environment is never printed", password not in out and "generated" not in out, out[-200:])
        for n in NAMES:
            c.check("%s exists again" % n, client.exists("accounts/" + n))

        # -- 03: HEAD ---------------------------------------------------------------
        out = run("03.accounts_name_HEAD.sh")
        c.check("03 prints the code and says the account exists", "HTTP 200" in out and "Account Exists" in out, out[-200:])
        out = run("03.accounts_name_HEAD.sh", ["example_nope"], expect_rc=1)
        c.check("03 says an account that is not there does not exist", "HTTP 404" in out and "Account does not exist" in out, out[-200:])

        # -- 04: GET one account several ways ------------------------------------------
        out = run("04.accounts_name_GET.sh")
        c.check("04 shows the refusal of a type specific field asked for without the type (not on the mock, which answers it)",
                ("HTTP 400" in out) == (not mock), out[-300:])
        c.check("and goes on to the call with the type, which answers the settings", out.count('"policy"') >= 1, out[-300:])
        run("04.accounts_name_GET.sh", ["example_nope"], expect_rc=1)
        # independently confirm the type specific field behaviour this script demonstrates
        with_type = client.get("accounts/" + USER, params={"type": "user", "fields": "addressBookSettings"}).json() or {}
        without_type = client.get("accounts/" + USER, params={"fields": "addressBookSettings"})
        c.check("a type specific field asked for with fields= still needs type= on this server",
                "addressBookSettings" in with_type and "addressBookSettings" not in (without_type.json() or {}), without_type.text[:200])

        # -- 05: PUT a new uid onto example_user, then the command it printed puts it back ----------
        before = account(USER)
        out = run("05.accounts_name_PUT.sh")
        c.check("the uid set by the script is visible", str(account(USER).get("uid")) == "1111", account(USER).get("uid"))
        c.check("05 says what the uid was, and how to put it back",
                "The uid of %s is now 41733." % USER in out and "To put it back: ./05.accounts_name_PUT.sh %s 41733" % USER in out, out[-300:])
        c.check("05 prints HTTP 204", "HTTP 204" in out)
        run("05.accounts_name_PUT.sh", [USER, "41733"])
        after = account(USER)
        c.check("the command it printed put the account back as it was",
                all(after.get(k) == before.get(k) for k in ("name", "uid", "gid", "homeFolder", "type", "notes")), (before.get("uid"), after.get("uid")))
        run("05.accounts_name_PUT.sh", [USER, "abc"], expect_rc=2)
        run("05.accounts_name_PUT.sh", ["example_nope"], expect_rc=1)
        for leftover in ("result.json", "new_result.json"):
            c.check("05 does not leave %s behind" % leftover, not os.path.exists(os.path.join(ACCOUNTS_DIR, leftover)))

        # -- 06: PATCH example_user ----------------------------------------------------
        settings_before = (account(USER, type="user").get("addressBookSettings") or {})
        contacts_before = len(settings_before.get("contacts") or [])
        out = run("06.accounts_name_PATCH.sh")
        settings = (account(USER, type="user").get("addressBookSettings") or {})
        contacts = settings.get("contacts") or []
        c.check("the new contact from 06 is present, after the %d there were" % contacts_before,
                len(contacts) == contacts_before + 1 and any(x.get("fullName") == "Jane Doe" for x in contacts), contacts)
        # A "remove" here does not drop the key from the object - confirmed directly: addressBookSettings
        # always carries this field, null when unset. "remove" resets it to that same null.
        c.check("nonAddressBookCollaborationAllowed was reset to null by remove", settings.get("nonAddressBookCollaborationAllowed") is None, settings)
        c.check("the policy is default", settings.get("policy") == "default", settings.get("policy"))
        sources = len(settings_before.get("sources") or [])
        c.check("06 prints HTTP 204 for each patch (the change to custom only with two sources, here %d)" % sources,
                out.count("HTTP 204") == (4 if sources >= 2 else 3), out.count("HTTP 204"))
        c.check("06 skips the change to custom when the sources are fewer than two, and says so",
                ("Skipping the change to custom" in out) == (sources < 2), out[:400])
        c.check("06 says what the settings were and how to put them back",
                "The address book settings of %s are now: policy default" % USER in out and "To put the policy and the flag back, PATCH this body: " in out, out[:500])
        # the body it printed for taking the contact out works
        taken = re.search(r"To take the contact out again, PATCH this body: (\[.*\])", out)
        if taken:
            response = client.patch("accounts/" + USER, json.loads(taken.group(1)))
            c.check("the body it printed takes the contact out again (204)", response.status == 204, response.text[:200])
            gone = (account(USER, type="user").get("addressBookSettings") or {}).get("contacts") or []
            c.check("and the contacts are as they were", len(gone) == contacts_before, gone)
        else:
            c.check("06 prints the body that takes the contact out again", False, out[-300:])
        run("06.accounts_name_PATCH.sh", ["example_nope"], expect_rc=1)
        out = run("06.accounts_name_PATCH.sh", [SERVICE], expect_rc=1)
        c.check("06 on a service account (which has no address book) is refused and says why", "Could not read the account" in out or "HTTP" in out, out[-300:])

        # -- 06 with a file: the sample bodies ------------------------------------------
        out = run("06.accounts_name_PATCH_with_file.sh")
        contacts = (account(USER, type="user").get("addressBookSettings") or {}).get("contacts") or []
        c.check("the contact from stPatchAccount.json is present via 06 with a file",
                any(x.get("fullName") == "Test 2Contact421" for x in contacts), contacts)
        c.check("06 with a file says what the path held, and prints HTTP 204",
                "What the paths hold now:" in out and "/addressBookSettings/contacts/-: null" in out and "HTTP 204" in out, out[-400:])
        run("06.accounts_name_PATCH_with_file.sh", [USER, os.path.join(BODY_DIR, "stPatchAccountNotes.json")])
        c.check("a second body, given as the second argument, set the notes", account(USER).get("notes") == "HelloWorld876", account(USER).get("notes"))
        if not mock:
            run("06.accounts_name_PATCH_with_file.sh", [USER, os.path.join(BODY_DIR, "stPatchAccountForcePasswordChange.json")])
            if client.exists("businessUnits/Pippin"):
                c.info('a business unit "Pippin" exists on this server: stPatchAccountBU.json is not run, it would move the account into it')
            else:
                home = account(USER).get("homeFolder")
                out = run("06.accounts_name_PATCH_with_file.sh", [USER, os.path.join(BODY_DIR, "stPatchAccountBU.json")], expect_rc=1)
                c.check("stPatchAccountBU.json names a business unit this server has not: refused, with its code", "HTTP 404" in out, out[-300:])
                c.check("and the account is as it was", account(USER).get("homeFolder") == home and account(USER).get("businessUnit") in (None, ""), account(USER).get("homeFolder"))
        run("06.accounts_name_PATCH_with_file.sh", [USER, os.path.join(BODY_DIR, "no_such_file.json")], expect_rc=2)
        bad = os.path.join(ACCOUNTS_DIR, ".zztest_not_a_patch.json")
        with open(bad, "w") as f:
            f.write('{"op": "add"}\n')
        try:
            run("06.accounts_name_PATCH_with_file.sh", [USER, bad], expect_rc=2)
        finally:
            os.remove(bad)
        run("06.accounts_name_PATCH_with_file.sh", ["example_nope"], expect_rc=1)

        # -- 07: delete the three accounts ------------------------------------------------
        run("07.accounts_name_DELETE.sh", ["", USER], expect_rc=2)
        c.check("07 with an empty name sent nothing: the accounts are still there", all(client.exists("accounts/" + n) for n in NAMES))
        out = run("07.accounts_name_DELETE.sh")
        c.check("07 says what it deletes, and prints HTTP 204 for each",
                out.count("Deleting Account:") == 3 and out.count("HTTP 204") == 3, out[-400:])
        for n in NAMES:
            c.check("%s is gone after 07.accounts_name_DELETE.sh" % n, not client.exists("accounts/" + n))
        out = run("07.accounts_name_DELETE.sh")
        c.check("07 run again says the accounts do not exist, exit 0", out.count("does not exist.") == 3, out[-300:])

finally:
    # Whatever happened, take away what this check made, and only that.
    for n in NAMES:
        if client.exists("accounts/" + n):
            client.delete("accounts/" + n)
            c.check("the leftover %s was removed" % n, not client.exists("accounts/" + n))
    if baseline_names is not None:
        now = sorted(a.get("name") for a in client.page("accounts"))
        c.check("the accounts of the server are the ones there were before this run", now == baseline_names,
                sorted(set(now) ^ set(baseline_names)))
    if john_before is not None:
        c.check('"john" is exactly as it was: no script of the folder touches it', account("john") == john_before)
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
