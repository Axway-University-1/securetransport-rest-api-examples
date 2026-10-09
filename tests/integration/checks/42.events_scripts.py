#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 23.Events examples against a
live event. An event exists only while a file is being processed, so this
builds a flow that holds one:

  an end user account, an Advanced Routing application, a subscription on a
  folder of that account, a route that sends what arrives to an SSH partner,
  and that partner: a TcpSink on this machine
  (tests/integration/lib/dummy_servers.py) that accepts the connection and
  never answers, so the server waits for it.

A file is uploaded to the folder with the real EndUser example. The server
starts the route, connects to the sink, and the event stays active while it
waits. The check then lists it with each filter, reads it, proves that a status
in capitals finds nothing, deletes it with 03.events_operations_POST_delete.sh
(together with an id that does not exist) and confirms it is gone.

Needs --write, st_allow_writes="yes", and st_callback_host in integration.conf:
this machine's address as the server sees it (see integration.conf.example).
Refuses to start when any of its example_events_* objects exist. Everything is
removed in a finally block, events first, and it never deletes an event of
another account.
"""
import base64
import contextlib
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402
import dummy_servers  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the events examples for real")
if not config.get("st_callback_host"):
    st_client.skip("st_callback_host is not set in integration.conf: the event needs a silent partner on this machine")

c = st_client.Checker("Events, run for real from Admin/API 2.0/bash/23.Events")
ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
FOLDER = os.path.join(ADMIN_TREE, "23.Events")
ACCOUNT, APPLICATION, SITE = "example_events_user_" + harness.suffix(), "example_events_app", "example_events_site"
TEMPLATE, SIMPLE, COMPOSITE = "example_events_template", "example_events_simple", "example_events_composite"
SUBSCRIPTION_FOLDER = "example_events"
# A name of its own each run: deleting an account leaves its home folder on disk, and a file
# that is already there is not a new arrival
UPLOAD_NAME = "example_events_%s.txt" % base64.b32encode(os.urandom(5)).decode().rstrip("=").lower()
PASSWORD = harness.new_password()
ENDUSER_PORT = harness.ports(config).enduser


script = harness.bind_script(c, FOLDER, timeout=90)


def my_events(routing_only=False):
    """The account's events; a short-lived DEFAULT one can appear first, for the arrival itself."""
    params = {"accountName": ACCOUNT, "limit": 100}
    if routing_only:
        params["processorType"] = "ADVANCED_ROUTING"
    return (admin.get("events", params=params).json() or {}).get("result", [])


def section(out, title):
    """The lines under a heading of 01.events_GET.sh's output."""
    for part in out.split("\n\n"):
        if part.startswith(title) or part.lstrip("\n").startswith(title):
            return part.split(":\n", 1)[-1]
    return ""


def by_name(path, name):
    return (admin.get(path, params={"name": name, "fields": "id"}).json() or {}).get("result", [])


def location_id(response):
    return response.headers.get("Location", "").rsplit("/", 1)[-1]


admin = harness.connect(config, c, mock="the bundled mock does not implement /events or the flow it needs")
if (admin.exists("applications/" + APPLICATION) or by_name("sites", SITE)
        or any(by_name("routes", n) for n in (TEMPLATE, SIMPLE, COMPOSITE))):
    c.check("none of the example_events_* objects exist yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

ids = {}
accounts = contextlib.ExitStack()
try:
    with dummy_servers.TcpSink() as sink:
        accounts.enter_context(harness.throwaway_account(admin, c, config, name=ACCOUNT, password=PASSWORD, label="set up: the account"))
        c.check("set up: the Advanced Routing application",
                admin.post("applications", {"type": "AdvancedRouting", "name": APPLICATION, "notes": "events check"}).status == 201)
        r = admin.post("subscriptions", {"type": "AdvancedRouting", "account": ACCOUNT, "application": APPLICATION,
                                         "folder": "/" + SUBSCRIPTION_FOLDER})
        ids["subscription"] = location_id(r)
        c.check("set up: the subscription", r.status == 201, r.text[:200])
        r = admin.post("sites", {"type": "ssh", "protocol": "ssh", "name": SITE, "account": ACCOUNT, "host": config["st_callback_host"],
                                 "port": str(sink.port), "userName": "x", "usePassword": True, "password": "x",
                                 "transferType": "partner", "uploadFolder": "/"})
        ids["site"] = location_id(r)
        c.check("set up: the SSH site, towards the silent partner", r.status == 201, r.text[:200])
        r = admin.post("routes", {"name": TEMPLATE, "description": "events check", "type": "TEMPLATE", "conditionType": "MATCH_ALL"})
        ids["template"] = location_id(r)
        c.check("set up: the route template", r.status == 201, r.text[:200])
        r = admin.post("routes", {"type": "SIMPLE", "name": SIMPLE, "conditionType": "ALWAYS", "condition": True, "steps": [
            {"type": "SendToPartner", "status": "ENABLED", "conditionType": "ALWAYS", "autostart": False, "usePrecedingStepFiles": False,
             "fileFilterExpressionType": "GLOB", "fileFilterExpression": "*", "transferSiteExpressionType": "LIST",
             "transferSiteExpression": SITE + "#!#CVD#!#", "actionOnStepFailure": "FAIL"}]})
        ids["simple"] = location_id(r)
        c.check("set up: the simple route that sends to the partner", r.status == 201, r.text[:200])
        r = admin.post("routes", {"type": "COMPOSITE", "account": ACCOUNT, "name": COMPOSITE, "conditionType": "MATCH_ALL",
                                  "routeTemplate": ids["template"], "subscriptions": [ids["subscription"]],
                                  "steps": [{"type": "ExecuteRoute", "status": "ENABLED", "autostart": False, "executeRoute": ids["simple"]}]})
        ids["composite"] = location_id(r)
        c.check("set up: the composite route on the subscription", r.status == 201, r.text[:200])

        enduser = st_client.EndUserClient(config["st_server"], ENDUSER_PORT, ACCOUNT, PASSWORD)
        enduser.login()
        enduser.create_folder(SUBSCRIPTION_FOLDER)
        for leftover in enduser.list_folder(SUBSCRIPTION_FOLDER) or []:
            enduser.delete_file("%s/%s" % (SUBSCRIPTION_FOLDER, leftover))
        enduser.logout()

        with runner.real_credentials(ADMIN_TREE, config):
            out = script("01.events_GET.sh", [ACCOUNT])
            c.check("01 before any upload there is no event of the account", not my_events() and "  %s  " % ACCOUNT not in out, out[-300:])
            script("03.events_operations_POST_delete.sh", expect_rc=2)

        with tempfile.TemporaryDirectory() as work:
            local = os.path.join(work, UPLOAD_NAME)
            with open(local, "w") as f:
                f.write("an event is made of this file\n")
            with runner.real_credentials(ENDUSER_TREE, dict(config, st_port=ENDUSER_PORT, st_user=ACCOUNT, st_password=PASSWORD)):
                result = runner.run(os.path.join(ENDUSER_TREE, "02.Files", "08.fileOperations_POST_upload.sh"), [local, SUBSCRIPTION_FOLDER],
                                    timeout=90)
                c.check("a file is uploaded to the subscribed folder with the real EndUser example", result.returncode == 0,
                        (result.stdout + result.stderr)[-300:])

        # A new event is "ready" while it waits to be taken, then "active" while it runs
        events, seen = [], []

        def event_is_active():
            global events
            events = my_events(routing_only=True)
            if events and events[0]["status"] not in seen:
                seen.append(events[0]["status"])
            return bool(events) and events[0]["status"] == "active"
        harness.wait_until(event_is_active, 90, 2)
        c.check("the server starts an event for the file, and it stays", len(events) == 1, events)
        c.check("a new event is ready, or already active, and becomes active", events and events[0]["status"] == "active", seen)
        if len(events) != 1 or events[0]["status"] != "active":
            raise SystemExit(c.done())
        event = events[0]
        target = "/home/%s/%s/%s" % (ACCOUNT, SUBSCRIPTION_FOLDER, UPLOAD_NAME)
        c.check("it is an active Advanced Routing event for the uploaded file",
                (event["status"], event["processorType"], event["fullTarget"]) == ("active", "ADVANCED_ROUTING", target),
                (event["status"], event["processorType"], event["fullTarget"]))
        harness.wait_until(lambda: bool(sink.connections), 15, 1)
        c.check("the server has connected to the silent partner, which is what keeps the event", len(sink.connections) >= 1,
                len(sink.connections))

        with runner.real_credentials(ADMIN_TREE, config):
            line = "  %s  active  %s  %s  retries 0" % (event["id"], ACCOUNT, target)
            out = script("01.events_GET.sh", [ACCOUNT, "active"])
            c.check("01 lists it, with its id, status, account, file and retries", line in section(out, "The events of the accounts matching"), out[-500:])
            c.check("01 and in the Advanced Routing only list", line in section(out, "Only the Advanced Routing ones"))
            c.check("01 and in the list with a heartbeat in the last hour", line in section(out, "With a heartbeat in the last hour"))
            out = script("01.events_GET.sh", ["example_events*"])
            c.check("01 the account pattern, with a wildcard, finds it too", line in section(out, "The events of the accounts matching"))
            out = script("01.events_GET.sh", [ACCOUNT, "ACTIVE"])
            c.check("01 a status in capitals finds nothing: it is matched exactly",
                    line not in section(out, "The events of the accounts matching") and line in section(out, "Only the Advanced Routing ones"), out[-500:])
            out = script("01.events_GET.sh", ["nobody_*"])
            c.check("01 another account's pattern does not list it", event["id"] not in out)

            out = script("02.events_id_GET.sh", [event["id"]])
            c.check("02 reads the event", "  active advancedRouting event for %s" % target in out and "  account %s, subscription" % ACCOUNT in out,
                    out[-400:])
            out = script("02.events_id_GET.sh")
            c.check("02 with no id it reads the first event listed", "event for" in out, out[-300:])
            out = script("02.events_id_GET.sh", ["0xNOSUCHEVENT"], expect_rc=1)
            c.check("02 an id that does not exist is refused with the server's reason", "Cannot find event" in out, out[-200:])

            before = len(my_events(routing_only=True))
            script("03.events_operations_POST_delete.sh", expect_rc=2)
            c.check("03 with no id nothing is deleted", len(my_events(routing_only=True)) == before)
            out = script("03.events_operations_POST_delete.sh", [event["id"], "0xNOSUCHEVENT"])
            c.check("03 deletes the event, and reports the id that does not exist", "  %s: deleted" % event["id"] in out
                    and "  0xNOSUCHEVENT: not found" in out, out[-300:])
            c.check("the event is gone from the list", not my_events(routing_only=True) and not admin.exists("events/" + event["id"]))
            out = script("03.events_operations_POST_delete.sh", [event["id"]])
            c.check("03 deleting it again says not found, and still exits 0", "  %s: not found" % event["id"] in out, out[-200:])
finally:
    # an event still running when the check ends outlives what it belongs to: delete it, until a read finds none
    def no_event_left():
        stuck = [e["id"] for e in my_events()]
        if stuck:
            admin.post("events/operations", {"ids": stuck}, params={"operation": "delete"})
        return not stuck
    harness.wait_until(no_event_left, 10, 2)
    for path in ("routes/" + ids.get("composite", ""), "routes/" + ids.get("template", ""), "subscriptions/" + ids.get("subscription", ""),
                 "sites/" + ids.get("site", ""), "applications/" + APPLICATION):
        if not path.endswith("/"):
            admin.delete(path)
    accounts.close()   # the files in its home folder, then the account
    c.check("nothing is left behind: no event, account, application, site or route", not my_events()
            and not admin.exists("accounts/" + ACCOUNT) and not admin.exists("applications/" + APPLICATION)
            and not by_name("sites", SITE) and not any(by_name("routes", n) for n in (TEMPLATE, SIMPLE, COMPOSITE)))
    admin.logout()

sys.exit(c.done())
