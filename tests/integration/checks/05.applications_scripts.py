#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified scripts in
Admin/API 2.0/bash/04.Applications against a configured server, in order, and
independently verifies every step through the API.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.

The scripts act on applications of their own, so nothing here is a substituted copy:
    example_humansystem   a flow application, created by 02, deleted by 07
    example_filepurge     a File Maintenance (AccountFilePurge) application, created by 02 with
                          no schedule, so that it never runs, deleted by 07
    example_archive       an ArchiveMaint application with a ONCE schedule, made by this check
                          through the API, to run 03 to 07 on an application that has a schedule
Every other application is left alone: the check keeps the list and compares it at the end. It
refuses to run when one of the three exists.

Only one application of a maintenance type is allowed per server, under any name (confirmed
directly: 400 "Application of type AccountFilePurge already exists. Only one instance of this
type is allowed.", with or without a schedule). A lab that already has an AccountFilePurge
application, as this one does, therefore gets no example_filepurge: 02 says so and creates the
flow application only, and 03 to 06 run on example_humansystem (and example_archive, for the
schedule) instead. That is a limit of the lab, not of the scripts: the creation of the File
Maintenance application is written from the reference and tested offline, and is checked here only
when the server has none.

What it expects: 02 (and 07, 03 to 06) that were run with no arguments used to create a real
AccountFilePurge application named "AccountFilePurge Application" that deleted *.txt files
after a ONCE schedule tomorrow, and delete it again by that name; they now act on the example_*
names above, print "HTTP <code>", exit 1 when the server refuses and tell the old value before
they change it. 06 patches the start date of a schedule that is in the future (it used to send
2025-02-21, which the server refuses: 400 "startDate occurs before the current moment.").
"""
import json
import os
import re
import sys
import datetime

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
FLOW, PURGE, ARCHIVE = "example_humansystem", "example_filepurge", "example_archive"
NAMES = [FLOW, PURGE, ARCHIVE]


def app_path(name):
    return "applications/" + name.replace(" ", "%20")


def script(name):
    return os.path.join(APPS_DIR, name)


def run(name, args=None, expect_rc=0, timeout=60):
    """Run a script, check its exit code, and give back its output."""
    result = runner.run(script(name), args, timeout=timeout)
    out = result.stdout + result.stderr
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc, out.strip()[-300:])
    return out


client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /applications; run this "
           "against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

baseline = None
try:
    with runner.real_credentials(BASH_TREE, config):

        pre_existing = [n for n in NAMES if client.exists(app_path(n))]
        if pre_existing:
            c.check("none of %s already exist on this server" % NAMES, False, pre_existing)
            c.info("refusing to run 02.applications_POST.sh: it would collide "
                   "with an application that is already there. Remove or "
                   "rename %s on the server, or point this at a cleaner lab." % pre_existing)
            client.logout()
            sys.exit(c.done())
        c.check("none of %s already exist on this server" % NAMES, True)

        baseline = client.get("applications", params={"limit": 500}).json()
        existing_purge = [a.get("name") for a in client.page("applications") if a.get("type") == "AccountFilePurge"]
        existing_archive = [a.get("name") for a in client.page("applications") if a.get("type") == "ArchiveMaint"]
        if existing_purge:
            c.info("this server already has an AccountFilePurge application (%s); only one is allowed per server, so "
                   "02.applications_POST.sh will say so and create the flow application only" % existing_purge)

        # -- 01: list applications ------------------------------------------------
        run("01.applications_GET.sh")

        # -- 02: a schedule that is not one is refused before anything is sent ------------
        run("02.applications_POST.sh", ["sometimes"], expect_rc=2)
        c.check("02 with a schedule that is not none or once created nothing", not any(client.exists(app_path(n)) for n in NAMES))

        # -- 02: create the flow application, and the maintenance one when the server has none ---
        out = run("02.applications_POST.sh")
        c.check("02 prints the HTTP code of each creation", out.count("HTTP 201") == (1 if existing_purge else 2), out[-400:])
        c.check("GET /%s now returns 200" % app_path(FLOW), client.get(app_path(FLOW)).status == 200)
        listed = {a.get("name") for a in client.page("applications")}
        c.check("%s is listed in GET /applications" % FLOW, FLOW in listed)
        targets = [FLOW]
        if existing_purge:
            c.check("02 says an application of type AccountFilePurge exists already, and creates none",
                    "exists already (%s)" % ", ".join(existing_purge) in out and not client.exists(app_path(PURGE)), out[-400:])
        else:
            targets.append(PURGE)
            purge = client.get(app_path(PURGE)).json() or {}
            c.check("%s is an AccountFilePurge application with no schedule, 90 days, *.txt" % PURGE,
                    (purge.get("type"), purge.get("deleteFilesDays"), purge.get("pattern"), purge.get("schedules")) == ("AccountFilePurge", 90, "*.txt", []),
                    purge)
        # a second run is refused by the server for the flow application (400, not 409), and the script says so by its exit code
        out = run("02.applications_POST.sh", expect_rc=1)
        c.check("the refusal of a duplicate shows its HTTP code and reason", "HTTP 400" in out and "already exists" in out, out[-400:])

        # -- an ArchiveMaint application with a schedule, from the API, to run 03 to 07 on one that has one ----
        archive_before = None
        if existing_archive:
            c.info("this server already has an ArchiveMaint application (%s): the schedule is not exercised" % existing_archive)
        else:
            tomorrow = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)).strftime("%Y-%m-%dT00:00:00Z")
            response = client.post("applications", {"type": "ArchiveMaint", "name": ARCHIVE, "schedules": [
                {"tag": "ArchiveMaint", "type": "ONCE", "executionTimes": ["00:00"], "startDate": tomorrow, "skipHolidays": False}]})
            c.check("created an ArchiveMaint application with a ONCE schedule, for 03 to 07", response.status == 201, response.text[:200])
            if response.status == 201:
                targets.append(ARCHIVE)
                archive_before = (client.get(app_path(ARCHIVE)).json() or {}).get("schedules")

        # -- 03: HEAD ---------------------------------------------------------------
        for n in targets:
            out = run("03.applications_name_HEAD.sh", [n])
            c.check("03 prints the code and says %s exists" % n, "HTTP 200" in out and "Application exists." in out, out[-200:])
        out = run("03.applications_name_HEAD.sh", ["example nope"], expect_rc=1)
        c.check("03 says an application that is not there does not exist (a name with a space, URL-encoded)",
                "HTTP 404" in out and "Application does not exist." in out, out[-200:])

        # -- 04: GET one application, including businessUnits -----------------------------
        for n in targets:
            out = run("04.applications_name_GET.sh", [n])
            c.check("04 says there are no business units for %s" % n, "No business units assigned to the application." in out, out[-200:])
        run("04.applications_name_GET.sh", ["example nope"], expect_rc=1)

        # -- 05: PUT new notes ----------------------------------------------------------------
        for n in targets:
            before = client.get(app_path(n)).json() or {}
            out = run("05.applications_name_PUT.sh", [n])
            after = client.get(app_path(n)).json() or {}
            c.check("the notes set by the PUT script are visible on %s" % n, str(after.get("notes", "")).startswith("New note "), after.get("notes"))
            c.check("05 says what the notes were, how to put them back, and prints HTTP 204",
                    "The notes of %s are now '%s'." % (n, before.get("notes") or "") in out and "To put them back: ./05.applications_name_PUT.sh %s" % n in out
                    and "HTTP 204" in out, out[-400:])
            c.check("the rest of %s is as it was (the whole object was sent back)" % n,
                    {k: v for k, v in after.items() if k != "notes"} == {k: v for k, v in before.items() if k != "notes"},
                    sorted(k for k in after if after.get(k) != before.get(k)))
            run("05.applications_name_PUT.sh", [n, before.get("notes") or ""])
            c.check("and the command it printed put the notes back", (client.get(app_path(n)).json() or {}).get("notes") == before.get("notes"))
        for leftover in ("tmp.json",):
            c.check("05.applications_name_PUT.sh does not leave %s behind" % leftover,
                    not os.path.exists(os.path.join(APPS_DIR, leftover)))
        run("05.applications_name_PUT.sh", ["example nope"], expect_rc=1)

        # -- 06: PATCH the notes and the schedule's startDate -----------------------------------
        for n in targets:
            before = client.get(app_path(n)).json() or {}
            out = run("06.applications_name_PATCH.sh", [n])
            after = client.get(app_path(n)).json() or {}
            c.check("the notes set by the PATCH script are visible on %s" % n, after.get("notes") == "Patched note", after.get("notes"))
            if before.get("schedules"):
                c.check("06 changed the start date of the schedule of %s, to a date after the one it had" % n,
                        int(after["schedules"][0]["startDate"]) > int(before["schedules"][0]["startDate"]), (before.get("schedules"), after.get("schedules")))
                body = re.search(r"The start date of the first schedule is now (\S+)\.\nTo put it back, PATCH this body: (\[.*\])", out)
                c.check("06 printed the old start date and the body that puts it back", bool(body), out[:600])
                if body:
                    restore = client.patch(app_path(n), json.loads(body.group(2)))
                    after_restore = (client.get(app_path(n)).json() or {}).get("schedules")
                    c.check("the body it printed restores the schedule exactly (start date and execution times)",
                            restore.status == 204 and after_restore == before.get("schedules"), (before.get("schedules"), after_restore))
            else:
                c.check("06 says %s has no schedule, so there is no startDate to change" % n,
                        "The application has no schedule, so there is no startDate to change." in out, out[-300:])
            c.check("06 prints HTTP 204 for each patch it sent", out.count("HTTP 204") == (2 if before.get("schedules") else 1), out[-400:])
            client.patch(app_path(n), [{"op": "replace", "path": "/notes", "value": before.get("notes") or ""}])
        out = run("06.applications_name_PATCH.sh", ["example nope"], expect_rc=1)
        c.check("06 on an application that is not there says so and sends no patch", "Could not read the application" in out and "HTTP 404" in out, out[-300:])

        # -- 07: delete the applications ------------------------------------------------------
        run("07.applications_name_DELETE.sh", ["", FLOW], expect_rc=2)
        c.check("07 with an empty name sent nothing: %s is still there" % FLOW, client.exists(app_path(FLOW)))
        out = run("07.applications_name_DELETE.sh")
        c.check("07 says what it deletes, prints HTTP 204 for each, and says the missing one is not there",
                out.count("HTTP 204") == len([t for t in targets if t != ARCHIVE])
                and (PURGE in targets or "Application %s does not exist." % PURGE in out), out[-500:])
        for n in (FLOW, PURGE):
            c.check("%s is gone after 07.applications_name_DELETE.sh" % n, not client.exists(app_path(n)))
        if ARCHIVE in targets:
            out = run("07.applications_name_DELETE.sh", [ARCHIVE])
            c.check("07 deletes the one it is given, and says what type it is", "Deleting application '%s' (type ArchiveMaint)" % ARCHIVE in out and "HTTP 204" in out, out[-300:])
            c.check("%s is gone" % ARCHIVE, not client.exists(app_path(ARCHIVE)))
        out = run("07.applications_name_DELETE.sh")
        c.check("07 run again says the applications do not exist, exit 0", out.count("does not exist.") == 2, out[-300:])

finally:
    # Whatever happened, take away what this check made, and only that.
    for n in NAMES:
        if client.exists(app_path(n)):
            client.delete(app_path(n))
            c.check("the leftover %s was removed" % n, not client.exists(app_path(n)))
    if baseline is not None:
        c.check("the applications of the server are the ones there were before this run",
                client.get("applications", params={"limit": 500}).json() == baseline)
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
