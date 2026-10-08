#!/usr/bin/env python3
"""
stGraceful.py, the most disruptive python example, run as a whole against a fake server.

It must never be run against the lab (tests/integration/checks/manual.graceful_scripts.py
records the outage an earlier run caused), so everything about it is checked here:

- it stops nothing without --yes, and sends nothing at all;
- every write carries the csrfToken (the fake refuses one that does not);
- a daemon is stopped once, by daemon=<protocol>, not by a serverName= the API does not take;
- it waits, bounded, for every daemon to be down, and stops the Transaction Manager only
  after that: a daemon that never stops ends the run with exit 1 and the TM untouched;
- every wait is bounded, in time that the fake clock moves on, so this runs in a moment.

Runs offline. Exit code 0 means clean.
"""
import copy
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import fake_st  # noqa: E402
import run_example  # noqa: E402

failures = 0
SCRIPT = "stGraceful.py"


def world(**extra):
    scenario = {
        "collections": {
            "servers": [
                {"serverName": "Ssh Default", "protocol": "ssh", "isActive": True},
                {"serverName": "Ftp Default", "protocol": "ftp", "isActive": True},
                {"serverName": "Http One", "protocol": "http", "isActive": True},
                {"serverName": "Http Two", "protocol": "http", "isActive": True},
                {"serverName": "Pesit Default", "protocol": "pesit", "isActive": True},
                {"serverName": "As2 Default", "protocol": "as2", "isActive": False},
            ],
            "clusterServices": [{"name": "FolderMonitor", "status": "Running."},
                                {"name": "Scheduler", "status": "Running."}],
        },
        "objects": {"transactionManager": {"status": "Running."}},
    }
    scenario.update(extra)
    return scenario


def stops(result, prefix):
    return [e for e in result.writes() if e["path"].startswith(prefix) and e["query"].get("operation") == "stop"]


# ----------------------------------------------------------------- the confirmation
c = fake_st.Checker("stGraceful.py: it stops nothing unless it is told to")
for label, args in (("no argument", []), ("seconds, and no --yes", ["30"]), ("--yes, and no seconds", ["--yes"]),
                    ("seconds that is not a number", ["soon", "--yes"]), ("two numbers", ["30", "40", "--yes"])):
    r = run_example.run(SCRIPT, args, world())
    c.check("%s: exit code 2" % label, r.returncode == 2, r.returncode)
    c.check("%s: nothing was sent" % label, r.calls == [], r.calls[:2])
r = run_example.run(SCRIPT, ["30"], world())
c.check("without --yes it says nothing was stopped and how to go on",
        "Nothing was sent" in r.output and "--yes" in r.output, r.output)
r = run_example.run(SCRIPT, ["30", "--yes"], world(), config={"st_server": None})
c.check("a config without a server is exit 1, not 0, and sends nothing", r.returncode == 1 and r.calls == [],
        (r.returncode, r.output))
failures += 0 if c.summary() else 1

# ----------------------------------------------------------------------- a clean run
print()
c = fake_st.Checker("stGraceful.py: a run to the end")
r = run_example.run(SCRIPT, ["30", "--yes"], world(), fast=True)
c.check("exit code 0", r.returncode == 0, r.output[-400:])
c.check("no traceback", "Traceback" not in r.output)
c.check("no write was refused: every one carried the csrfToken and the Referer", r.violations() == [], r.violations())
c.check("it logged out with the csrfToken too",
        any(e["method"] == "DELETE" and e["path"] == "myself" and e["has_csrf"] for e in r.calls))
daemon_stops = stops(r, "daemons/operations")
c.check("each protocol that was running is stopped once, by daemon=",
        sorted(e["query"].get("daemon") for e in daemon_stops) == ["ftp", "http", "pesit", "ssh"],
        [e["query"] for e in daemon_stops])
c.check("it does not send a serverName to /daemons/operations",
        all("serverName" not in e["query"] for e in daemon_stops))
c.check("the stop is graceful, with the seconds it was given",
        all(e["query"].get("graceful") == "true" and e["query"].get("timeout") == "30" for e in daemon_stops))
c.check("a daemon that was not running (as2) is not stopped",
        all(e["query"].get("daemon") != "as2" for e in daemon_stops))
services = stops(r, "clusterServices/operations")
c.check("FolderMonitor and Scheduler are stopped",
        sorted(e["query"].get("serviceName") for e in services) == ["FolderMonitor", "Scheduler"])
tm = stops(r, "transactionManager/operations")
c.check("the Transaction Manager is stopped once, with the seconds", len(tm) == 1 and tm[0]["query"].get("timeout") == "30", tm)
c.check("and only after every server was down", tm and tm[0].get("servers_active") == [], tm)
order = [e["path"] for e in r.writes()]
c.check("services first, then daemons, then the Transaction Manager",
        order.index("transactionManager/operations") == len(order) - 1
        and all(order.index("clusterServices/operations") < i for i, p in enumerate(order) if p == "daemons/operations"), order)
failures += 0 if c.summary() else 1

# ------------------------------------------------------------------ waiting, bounded
print()
c = fake_st.Checker("stGraceful.py: it waits for the daemons, and not forever")
r = run_example.run(SCRIPT, ["30", "--yes"], world(stop_lag=3), fast=True)
tm = stops(r, "transactionManager/operations")
c.check("daemons that take a few rounds to go down: exit 0", r.returncode == 0, r.output[-400:])
c.check("it slept between the rounds, once per round, not once per protocol",
        0 < len(r.sleeps) <= 6, r.sleeps)
c.check("and the Transaction Manager waited for every server to be down", tm and tm[0].get("servers_active") == [], tm)
c.check("a daemon is still stopped only once while it is being waited for",
        len(stops(r, "daemons/operations")) == 4, [e["query"] for e in stops(r, "daemons/operations")])

r = run_example.run(SCRIPT, ["30", "--yes"], world(stop_lag=100000), fast=True)
c.check("a daemon that never stops: exit code 1", r.returncode == 1, (r.returncode, r.output[-300:]))
c.check("the Transaction Manager was NOT stopped", stops(r, "transactionManager/operations") == [])
c.check("it says so", "NOT stopped" in r.output, r.output[-300:])
c.check("it gave up after the seconds plus the margin, not at once and not forever",
        85 <= sum(r.sleeps) <= 110, sum(r.sleeps))
c.check("no traceback", "Traceback" not in r.output)

r = run_example.run(SCRIPT, ["30", "--yes"], world(service_lag=100000), fast=True)
c.check("a cluster service that never stops: exit code 1", r.returncode == 1, (r.returncode, r.output[-300:]))
c.check("then no daemon and not the Transaction Manager is touched",
        stops(r, "daemons/operations") == [] and stops(r, "transactionManager/operations") == [], r.writes())
c.check("and the wait for it is bounded", sum(r.sleeps) <= 140, sum(r.sleeps))
failures += 0 if c.summary() else 1

# ---------------------------------------------------------------- every kind of failure
print()
c = fake_st.Checker("stGraceful.py: every failure is exit 1, with no traceback, and stops nothing more")
cases = (("a connection error on every call", {"kind": "raise:ConnectionError"}),
         ("a timeout on every call", {"kind": "raise:Timeout"}),
         ("the login refused with 401", {"kind": "status:401", "on": "login"}),
         ("the login answering 500", {"kind": "status:500", "on": "login"}),
         ("a timeout after the login", {"kind": "raise:Timeout", "on": "after_login"}),
         ("a connection error after the login", {"kind": "raise:ConnectionError", "on": "after_login"}),
         ("401 after the login", {"kind": "status:401", "on": "after_login"}),
         ("500 after the login", {"kind": "status:500", "on": "after_login"}),
         ("500 on the daemon stop only", {"kind": "status:500", "on": "after_login", "path": "daemons/operations"}),
         ("500 on the cluster service stop only", {"kind": "status:500", "on": "after_login", "path": "clusterServices/operations"}),
         ("500 reading the servers", {"kind": "status:500", "on": "after_login", "path": "servers"}))
for label, fail in cases:
    r = run_example.run(SCRIPT, ["30", "--yes"], world(fail=fail), fast=True)
    c.check("%s: exit 1" % label, r.returncode == 1, (r.returncode, r.output[-200:]))
    c.check("%s: no traceback" % label, "Traceback" not in r.output, r.output[-300:])
    c.check("%s: the Transaction Manager was not stopped" % label, stops(r, "transactionManager/operations") == [])

r = run_example.run(SCRIPT, ["30", "--yes"], world(fail={"kind": "status:500", "on": "after_login", "method": "POST", "path": "transactionManager"}), fast=True)
c.check("the Transaction Manager stop answering 500 is exit 1", r.returncode == 1, (r.returncode, r.output[-200:]))
r = run_example.run(SCRIPT, ["30", "--yes"], world(fail={"kind": "raise:ConnectionError", "on": "after_login", "method": "DELETE"}), fast=True)
c.check("a logout that cannot connect, after everything was stopped, is a warning, exit 0",
        r.returncode == 0 and "did not work" in r.output and "Traceback" not in r.output, (r.returncode, r.output[-300:]))

r = run_example.run(SCRIPT, ["30", "--yes"], world(), fast=True, config={"st_edge_server": "edge.example.com"})
logins = [e for e in r.calls if e["method"] == "POST" and e["path"] == "myself"]
c.check("an edge server is logged into as well, and out of", len(logins) == 2 and
        len([e for e in r.calls if e["method"] == "DELETE" and e["path"] == "myself"]) == 2, len(logins))
c.check("and that run is clean", r.returncode == 0 and r.violations() == [], (r.returncode, r.violations()))
r = run_example.run(SCRIPT, ["30", "--yes"], world(), fast=True, config={"st_ca_bundle": "/etc/ssl/example-ca.pem"})
c.check("st_ca_bundle reaches every call", r.calls and all(e["verify"] == "/etc/ssl/example-ca.pem" for e in r.calls),
        set(e["verify"] for e in r.calls))
r = run_example.run(SCRIPT, ["30", "--yes"], world(), fast=True)
c.check("by default the certificate is not checked", r.calls and all(e["verify"] is False for e in r.calls))
failures += 0 if c.summary() else 1

# ------------------------------------------------------- functions, in this process
print()
c = fake_st.Checker("stGraceful.py: the functions")
ns = fake_st.load(SCRIPT)
s = fake_st.FakeSession({"servers": [{"isActive": True}]})
c.check("an active server whose answer has no protocol does not break the status check",
        ns["getServerDaemonsStatus"](s, "https://st.example.com:8444/api/v2.0/", "T", "ssh") is True)
s = fake_st.FakeSession({"servers": [{"protocol": "ssh", "isActive": False}]})
c.check("an inactive one is not running", ns["getServerDaemonsStatus"](s, "https://st.example.com:8444/api/v2.0/", "T", "ssh") is False)
failures += 0 if c.summary() else 1

print()
if failures:
    print("test_python_graceful: FAIL (%d group(s))" % failures)
    sys.exit(1)
print("test_python_graceful: PASS")
