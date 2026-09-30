#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified scripts in
Admin/API 2.0/bash/04.Applications against a configured server, in order, and
independently verifies every step through the API.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.

Objects touched, by the literal names the scripts use:
    "AccountFilePurge Application" and "HumanSystem Application"
        created by 02, deleted by 07

Until recently, 03.applications_name_HEAD.sh and 07.applications_name_DELETE.sh
named two different applications here - "Audit Log Maintenance" and "Transfer
Log Maintenance". On a real server those are the built-in AuditLogMaint and
TransferLogMaint housekeeping jobs, not test data: running the DELETE script as
it shipped would have deleted real maintenance jobs, not cleaned up after this
folder's own POST script. That was fixed before this check was written; see the
Notes in 03 and 07 for the detail. This check's pre-flight below still refuses
to run if either of the two names it actually uses already exists, on the same
principle - never assume a name is disposable just because an example uses it.

Also confirmed against a real server: only one application of a given
maintenance type is allowed at all, under any name. 02.applications_POST.sh
checks for this before creating one (like it already did for the flow type) -
so if this server already has an AccountFilePurge application under a
different name, 02 will correctly skip creating "AccountFilePurge Application"
rather than fail. That leaves 04 through 06 with nothing of that name to act
on, since those three demonstrate GET/PUT/PATCH on one specific application.

Rather than skip the whole run, this check falls back: 04, 05 and 06 are each
run as a name-substituted copy (script_runner.substituted_copy) targeting
"HumanSystem Application" instead - the flow-type application 02 creates
regardless of the AccountFilePurge collision, since flow type has no such
singleton constraint. That is not the same as running the real files against
the name they actually hardcode. A type swap was considered and rejected: an
AccountFilePurge-shaped PUT/PATCH body is not valid for every maintenance
type - confirmed directly, an AccountTTL application rejects the
AccountFilePurge fields this script sends with a 400. Retargeting at the
already-successfully-created HumanSystem application sidesteps that schema
difference entirely, at the cost of exercising a flow type application
instead of a maintenance type one for those three scripts.

01, 02, 03 and 07 always run unmodified: 02's own pre-check is what produces
the collision-safe behavior above, 03's assertions already only depend on
HumanSystem existing, and 07's plain DELETE on a name that never existed is a
harmless 404, not an error.
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
    st_client.skip("read only run, pass --write to run the applications scripts for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Applications, run for real from Admin/API 2.0/bash/04.Applications")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
APPS_DIR = os.path.join(BASH_TREE, "04.Applications")
NAMES = ["AccountFilePurge Application", "HumanSystem Application"]


def url_name(name):
    return "applications/" + name.replace(" ", "%20")


def script(name):
    return os.path.join(APPS_DIR, name)


def run_and_report(name, timeout=60):
    result = runner.run(script(name), timeout=timeout)
    c.check("%s runs without a shell level error" % name, result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")
    return result


client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /applications; run this "
           "against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

try:
    with runner.real_credentials(BASH_TREE, config):

        pre_existing = [n for n in NAMES if client.exists(url_name(n))]
        if pre_existing:
            c.check("none of %s already exist on this server" % NAMES, False, pre_existing)
            c.info("refusing to run 02.applications_POST.sh: it would collide "
                   "with an application that is already there. Remove or "
                   "rename %s on the server, or point this at a cleaner lab."
                   % pre_existing)
            client.logout()
            sys.exit(c.done())
        c.check("none of %s already exist on this server" % NAMES, True)

        existing_of_type = [a.get("name") for a in client.page("applications")
                            if a.get("type") == "AccountFilePurge"]
        fallback_target = None
        if existing_of_type:
            fallback_target = "HumanSystem Application"
            c.info("this server already has an AccountFilePurge application "
                   "(%s); only one is allowed per server, so "
                   "02.applications_POST.sh will correctly skip creating "
                   '"AccountFilePurge Application". 04 through 06 below will '
                   'run as name-substituted copies targeting "%s" instead - '
                   "see this check's own docstring for what that does and "
                   "does not prove." % (existing_of_type, fallback_target))

        # -- 01: list applications ------------------------------------------------
        run_and_report("01.applications_GET.sh")

        # -- 02: create the two applications (or one, if AccountFilePurge --------
        # -- already exists elsewhere - see fallback_target above) ---------------
        run_and_report("02.applications_POST.sh")

        for n in NAMES:
            if n == "AccountFilePurge Application" and fallback_target:
                continue  # 02 correctly skipped creating this one; nothing to check
            c.check("GET /%s now returns 200" % url_name(n),
                    client.get(url_name(n)).status == 200)
        listed = {a.get("name") for a in client.page("applications")}
        for n in NAMES:
            if n == "AccountFilePurge Application" and fallback_target:
                continue
            c.check("%s is listed in GET /applications" % n, n in listed)

        # -- 03: HEAD checks on both applications ---------------------------------
        result = run_and_report("03.applications_name_HEAD.sh")
        c.check("the script's own output reports both applications exist",
                result.stdout.count("Application exists.") >= 1
                and "Application does not exist." not in result.stdout,
                result.stdout[-200:])

        target = fallback_target or "AccountFilePurge Application"
        subs = ({} if not fallback_target else
                {"AccountFilePurge%20Application": "HumanSystem%20Application"})

        def run_targeted(name):
            if fallback_target:
                with runner.substituted_copy(script(name), subs) as copy:
                    return run_and_report(os.path.basename(copy))
            return run_and_report(name)

        label_suffix = " (name-substituted copy targeting %s)" % target if fallback_target else ""

        # -- 04: GET AccountFilePurge Application, including businessUnits --------
        run_targeted("04.applications_name_GET.sh")

        # -- 05: PUT a new notes value ---------------------------------------------
        run_targeted("05.applications_name_PUT.sh")
        after = client.get(url_name(target)).json() or {}
        c.check("the notes set by the PUT script are visible" + label_suffix,
                str(after.get("notes", "")).startswith("New note "), after.get("notes"))
        for leftover in ("tmp.json",):
            c.check("05.applications_name_PUT.sh does not leave %s behind" % leftover,
                    not os.path.exists(os.path.join(APPS_DIR, leftover)))

        # -- 06: PATCH the notes and the schedule's startDate ----------------------
        run_targeted("06.applications_name_PATCH.sh")
        after = client.get(url_name(target)).json() or {}
        c.check("the notes set by the PATCH script are visible" + label_suffix,
                after.get("notes") == "Patched note", after.get("notes"))
        schedules = after.get("schedules") or []
        if fallback_target:
            c.info('the schedule startDate PATCH in 06 targets '
                   '/schedules/0/startDate, which only exists on a '
                   'maintenance type application - "%s" is a flow type '
                   "application with no schedules array, so that second "
                   "PATCH call is expected to fail against it (the script "
                   "does not check its own response code, so this does not "
                   "show up as a shell level error above). Not asserting on "
                   "it in fallback mode." % target)
        else:
            c.check("the schedule startDate set by the PATCH script is visible",
                    bool(schedules) and schedules[0].get("startDate") == "2025-02-21T02:30:00Z",
                    schedules)

        # -- 07: delete both applications -------------------------------------------
        run_and_report("07.applications_name_DELETE.sh")
        for n in NAMES:
            c.check("%s is gone after 07.applications_name_DELETE.sh" % n,
                    not client.exists(url_name(n)))

finally:
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
