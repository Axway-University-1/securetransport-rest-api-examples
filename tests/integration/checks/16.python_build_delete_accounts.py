#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs stBuildTestAccounts.py and the real, unmodified
stDeleteTestAccounts.py in Admin/API 2.0/python/python3 against a configured
server, and independently verifies both.

stBuildTestAccounts.py is a dry run unless given --apply, takes the prefix and the
count as arguments (here ZZ and 3), and makes sure a business unit named
"CatFoodCorporation" is there (it is not check-before-create in the sense of
leaving a real one alone only for the accounts: an existing unit is kept, a
missing one created). This check runs a copy with the business unit renamed to
"ZZTEST_CatFoodCorporation", so a real business unit of that name is never at
risk and cleanup is unambiguous. That is not the same as running the real file -
see script_runner.substituted_copy. The accounts themselves are named
"ZZ0".."ZZ2", which is what stDeleteTestAccounts.py (a dry run unless --apply, and
a match on the START of the name, with the same default prefix ZZ) is built to
find, so that script runs completely unmodified.

The dry run of both is checked first: nothing is created, nothing is deleted.

Needs tests/local/pyvenv - see 15.python_read_scripts.py's docstring for how
to create it.

Confirmed and fixed while getting this running the first time - real bugs in
both shipped scripts, not just a macOS quirk:

  - Both scripts crashed with NameError: name 'base64' is not defined. Their
    main block never imports base64 at all, despite using base64.b64encode
    directly - only the per-process worker function's own (separately
    scoped) import covers that function, not the main block.
  - Both worker functions (stCreateAccount, stDeleteAccount) call the shared
    stLogin()/stLogout() helpers, which read stUrl, referer, stTimeout and
    apiCount as module globals rather than function arguments. Those globals
    are only ever set inside `if __name__ == "__main__":` in the *parent*
    process. Confirmed directly: under macOS/Windows multiprocessing, whose
    default "spawn" start method re-imports the module fresh in the child
    rather than inheriting the parent's already-executed globals the way a
    forked child (Linux's default) would, this raised NameError on stUrl the
    moment a worker process tried to log in. stDeleteAccount separately
    called stLogin(basicAuth, ...) - the same undefined global, and not even
    the local `auth` argument it was actually given. Both are fixed by
    seeding the globals stLogin/stLogout need from each worker's own
    arguments before calling either. See the gotchas skill.

Safety: refuses to run at all if any of ZZ0, ZZ1, ZZ2 or the throwaway
business unit already exist, the same as this repository's other accounts
checks refuse to collide with something already there.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the build/delete scripts for real")

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

c = st_client.Checker("Python build/delete test accounts, run for real from "
                       "Admin/API 2.0/python/python3")

PY_TREE = runner.path("Admin", "API 2.0", "python")
PY_DIR = os.path.join(PY_TREE, "python3")
NAMES = ["ZZ0", "ZZ1", "ZZ2"]
BU_NAME = "ZZTEST_CatFoodCorporation"


def script(name):
    return os.path.join(PY_DIR, name)


client = harness.connect(config, c, mock=("the bundled mock does not implement enough of the admin API for "
                                          "these scripts; run this against a real server to exercise it"))

created = False

try:
    pre_existing = [n for n in NAMES if client.exists("accounts/" + n)]
    if client.exists("businessUnits/" + BU_NAME):
        pre_existing.append(BU_NAME)
    if pre_existing:
        c.check("none of %s already exist on this server" % (NAMES + [BU_NAME]),
                False, pre_existing)
        c.info("refusing to run: it would collide with something already "
               "there. Remove %s by hand, or point this at a cleaner lab."
               % pre_existing)
        client.logout()
        sys.exit(c.done())
    c.check("none of %s already exist on this server" % (NAMES + [BU_NAME]), True)

    # stDeleteTestAccounts.py deletes every user account whose name starts with ZZ, and this
    # check runs it for real: with any other such account on the server it would delete that too
    def other_zz_accounts():
        return [a["name"] for a in client.page("accounts", params={"type": "user"})
                if a["name"].startswith("ZZ") and a["name"] not in NAMES]

    other = other_zz_accounts()
    if other:
        c.info("refusing to run: stDeleteTestAccounts.py would also delete these user accounts "
               "whose name starts with ZZ: %s. Remove them, or run this when nothing else is "
               "using the lab." % other)
        c.check("no other user account starts with ZZ on this server", False, other)
        client.logout()
        sys.exit(c.done())
    c.check("no other user account starts with ZZ on this server", True)

    subs = {
        "numberParallelProcesses = 3": "numberParallelProcesses = 1",
        "'name': 'CatFoodCorporation',": "'name': '%s'," % BU_NAME,
        "'baseFolder' : '/usrdata/CatFoodCo'": "'baseFolder' : '/usrdata/ZZTEST_CatFoodCo'",
    }

    with runner.real_credentials_python(PY_TREE, config):
        with runner.substituted_copy(script("stBuildTestAccounts.py"), subs) as copy:
            result = runner.run_python(copy, ["ZZ", "3"], timeout=60)
            c.check("stBuildTestAccounts.py without --apply is a dry run: exit 0, nothing created",
                    result.returncode == 0 and "DRY RUN" in result.stdout
                    and not any(client.exists("accounts/" + n) for n in NAMES)
                    and not client.exists("businessUnits/" + BU_NAME),
                    result.stdout[-300:])

            result = runner.run_python(copy, ["--apply", "ZZ", "3"], timeout=60)
            c.check("stBuildTestAccounts.py --apply runs without a shell level error "
                    "(business unit renamed, 3 accounts, 1 process)", result.returncode == 0,
                    (result.stdout + result.stderr).strip()[-300:] if result.returncode else "")

        created = client.exists("businessUnits/" + BU_NAME)
        for n in NAMES:
            c.check("%s exists after the build script" % n, client.exists("accounts/" + n))
        c.check("the throwaway business unit exists after the build script", created)

        result = runner.run_python(script("stDeleteTestAccounts.py"), timeout=60)
        c.check("stDeleteTestAccounts.py without --apply is a dry run: it lists ZZ0..ZZ2, exit 0, deletes nothing",
                result.returncode == 0 and "DRY RUN" in result.stdout
                and all(n in result.stdout for n in NAMES)
                and all(client.exists("accounts/" + n) for n in NAMES),
                (result.stdout + result.stderr)[-400:])
        listed = result.stdout
        c.check("it listed the three accounts and no other (3 of the user accounts start with ZZ)",
                "3 of " in listed and "john" not in listed.replace("DRY", ""), listed[-400:])

        # something else may have made a ZZ account since the check above: do not delete it
        other = other_zz_accounts()
        if other:
            c.info("not running --apply: another user account whose name starts with ZZ "
                   "appeared: %s" % other)
        else:
            result = runner.run_python(script("stDeleteTestAccounts.py"), ["--apply"], timeout=60)
            c.check("stDeleteTestAccounts.py --apply runs without a shell level error",
                    result.returncode == 0,
                    (result.stdout + result.stderr).strip()[-300:] if result.returncode else "")

            for n in NAMES:
                c.check("%s is gone after stDeleteTestAccounts.py" % n,
                        not client.exists("accounts/" + n))

finally:
    if created:
        client.delete("businessUnits/" + BU_NAME)
        c.check("the throwaway business unit was removed",
                not client.exists("businessUnits/" + BU_NAME))
    for n in NAMES:
        if client.exists("accounts/" + n):
            client.delete("accounts/" + n)
            c.check("%s was removed in cleanup (stDeleteTestAccounts.py missed it)" % n,
                    not client.exists("accounts/" + n))
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own calls)"
       % client.calls)

sys.exit(c.done())
