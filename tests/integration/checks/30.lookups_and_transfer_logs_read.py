#!/usr/bin/env python3
"""
Read only. Checks the query filters and counts the newer examples rely on,
then runs the real read scripts and compares what they print with what the
API answers directly.

The filters, each confirmed by asking for it and checking every object that
comes back, using objects already on the server:

  - GET /sites?account=A, and ?account=A&name=N, used by
    06.TransferSites/03.sites_GET.sh and 04.sites_id_DELETE.sh
  - GET /subscriptions?account=A, used by 07.Subscriptions/01, 04 and
    09.CompositeRoutes/05
  - GET /routes?type=T and ?name=N, used by 09.CompositeRoutes/05, 06 and 07
  - GET /logs/transfers?status=Failed and ?account=A, used by 16.TransferLogs and
    stBillableTransfers.py. Not ?accountName=A: the endpoint ignores it
    without a word and answers for every account (confirmed directly)

A filter the server ignored would come back with objects that do not match,
and an example that deletes "the first match" would then delete the wrong
object. That is why each one is checked here, before the --write check (31)
runs the delete examples.

The counts:

  - /logs/transfers carries resultSet.totalCount, and returnCount is capped by
    limit, which is why 16.TransferLogs and stBillableTransfers.py read
    totalCount
  - 16.TransferLogs/01.logs_transfers_GET.sh prints the same total the API
    gives for the account
  - 16.TransferLogs/02.logs_transfers_GET_billable.sh, and
    stBillableTransfers.py when tests/local/pyvenv exists, print per-day
    billable counts that match the API's own count for the same day. Only on
    5.5-20260924 or later, which classifies transfers as billable.

A transfer that finishes while this runs can move a count, so each printed
count is checked to lie between the API's count just before and just after
the script ran.

When the server has no sites, subscriptions or transfers to test a filter
with, that part says so and is not counted as a failure.
"""
import datetime
import email.utils
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

c = st_client.Checker("Lookups and transfer logs the newer examples rely on (read only)")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
LOGS_DIR = os.path.join(BASH_TREE, "16.TransferLogs")
PY_TREE = runner.path("Admin", "API 2.0", "python")
BILLABLE_RELEASE = "5.5-20260924"

client = harness.connect(config, c, mock=("the bundled mock does not implement /sites, /subscriptions, /routes "
                                          "or /logs/transfers; run this against a real server to exercise it"))


def results(path, params):
    response = client.get(path, params=params)
    return response.status, (response.json() or {}).get("result", [])


def check_filter(label, path, params, key, value):
    """Every object a filtered GET returns carries the value filtered on."""
    status, items = results(path, params)
    wrong = [i.get(key) for i in items if i.get(key) != value]
    c.check("%s: GET /%s?%s returns only matches (%d returned)"
            % (label, path, "&".join("%s=%s" % kv for kv in params.items()), len(items)),
            status == 200 and items and not wrong, wrong[:5] or status)


def total_of(params):
    return ((client.get("logs/transfers", params=params).json() or {})
            .get("resultSet", {}).get("totalCount"))


def billable_count(day, account=None):
    start = datetime.datetime.combine(day, datetime.time()).astimezone()
    end = datetime.datetime.combine(day + datetime.timedelta(days=1), datetime.time()).astimezone()
    params = {"isBillable": "true", "startTimeAfter": email.utils.format_datetime(start),
              "endTimeBefore": email.utils.format_datetime(end), "limit": 1, "fields": "id"}
    if account:
        params["account"] = account
    return ((client.get("logs/transfers", params=params).json() or {})
            .get("resultSet", {}).get("totalCount"))


def check_daily_counts(label, run_script, days, account=None):
    """Run a per-day billable report, and compare each day with the API."""
    st_client.avoid_midnight()
    today = datetime.date.today()
    window = [today - datetime.timedelta(days=n) for n in range(days - 1, -1, -1)]
    before = [billable_count(d, account) for d in window]
    result = run_script()
    after = [billable_count(d, account) for d in window]

    c.check(label + " runs without an error", result.returncode == 0,
            (result.stdout + result.stderr).strip()[-300:])
    printed = dict(re.findall(r"^\s+(\d{4}-\d{2}-\d{2})\s+(\d+)\s*$", result.stdout, re.M))
    c.check(label + " prints one line per day, %d in all" % days,
            sorted(printed) == [d.isoformat() for d in window], sorted(printed))
    for d, low, high in zip(window, before, after):
        got = printed.get(d.isoformat())
        ok = got is not None and low is not None and high is not None and low <= int(got) <= high
        c.check("%s: %s matches the API (%s, API %s..%s)" % (label, d, got, low, high), ok)


try:
    # -- the lookups the delete examples depend on -------------------------
    status, sites = results("sites", {"limit": 50})
    owned = [s for s in sites if s.get("account") and s.get("name")]
    if owned:
        site = owned[0]
        check_filter("sites", "sites", {"account": site["account"]}, "account", site["account"])
        status, found = results("sites", {"account": site["account"], "name": site["name"], "fields": "id"})
        c.check("sites: ?account=&name=&fields=id finds that one site, by id",
                status == 200 and [f.get("id") for f in found] == [site["id"]],
                [f.get("id") for f in found])
    else:
        c.info("no site on this server is attached to an account; the /sites filters are not tested")

    status, subs = results("subscriptions", {"limit": 50})
    accounts = [s.get("account") for s in subs if s.get("account")]
    if accounts:
        check_filter("subscriptions", "subscriptions", {"account": accounts[0]}, "account", accounts[0])
    else:
        c.info("no subscriptions on this server; the /subscriptions filter is not tested")

    for route_type in ("COMPOSITE", "SIMPLE", "TEMPLATE"):
        status, routes = results("routes", {"type": route_type, "limit": 50})
        if routes:
            check_filter("routes", "routes", {"type": route_type, "limit": 50}, "type", route_type)
        else:
            c.info("no %s routes on this server; ?type=%s is not tested" % (route_type, route_type))
    status, routes = results("routes", {"limit": 1})
    if routes:
        check_filter("routes", "routes", {"name": routes[0]["name"]}, "name", routes[0]["name"])

    # -- the transfer log ---------------------------------------------------
    response = client.get("logs/transfers", params={"limit": 1})
    result_set = (response.json() or {}).get("resultSet", {})
    total = result_set.get("totalCount")
    c.check("GET /logs/transfers carries resultSet.totalCount", total is not None, result_set)
    c.check("returnCount is capped by limit=1", (result_set.get("returnCount") or 0) <= 1, result_set)
    if total and total >= 2:
        c.check("so with limit=1, only totalCount gives the real number (%s)" % total,
                result_set.get("returnCount") == 1 and total > 1, result_set)

    status, failed = results("logs/transfers", {"status": "Failed", "limit": 20})
    if failed:
        statuses = sorted(set(str(f.get("status")) for f in failed))
        c.check("?status=Failed returns only failed transfers", statuses == ["Failed"], statuses)
    else:
        c.info("no failed transfers in the log; ?status=Failed is not tested")

    # The account of the latest transfer, to run 16.TransferLogs/01 with
    latest = results("logs/transfers", {"limit": 1})[1]
    account = latest[0].get("account") if latest else None
    if account:
        # account= filters; accountName= is ignored without a word and answers
        # for every account, which is how the scripts once counted everything
        check_filter("logs", "logs/transfers", {"account": account, "limit": 50}, "account", account)
        everyone = total_of({"limit": 1})
        ignored = total_of({"accountName": "zz-no-such-account-zz", "limit": 1})
        c.info("accountName= is %s by this server (an unknown account: %s of %s entries)"
               % ("ignored" if ignored == everyone else "applied", ignored, everyone))

    with runner.real_credentials(BASH_TREE, config):
        if account:
            def account_total():
                return ((client.get("logs/transfers", params={"account": account, "limit": 1})
                         .json() or {}).get("resultSet", {}).get("totalCount"))
            low = account_total()
            result = runner.run(os.path.join(LOGS_DIR, "01.logs_transfers_GET.sh"), [account])
            high = account_total()
            c.check("16.TransferLogs/01.logs_transfers_GET.sh runs without an error",
                    result.returncode == 0, result.stderr.strip()[-300:])
            match = re.search(r"^(\d+) transfer\(s\) of '%s' in the log, in all\." % re.escape(account),
                              result.stdout, re.M)
            got = int(match.group(1)) if match else None
            c.check("16.TransferLogs/01 prints the account's total, as the API counts it "
                    "(%s, API %s..%s)" % (got, low, high),
                    got is not None and low is not None and low <= got <= high)
        else:
            c.info("the transfer log is empty, or its entries carry no account; "
                   "16.TransferLogs/01.logs_transfers_GET.sh is not run")

        if st_client.server_release_at_least(client, BILLABLE_RELEASE):
            billable_script = os.path.join(LOGS_DIR, "02.logs_transfers_GET_billable.sh")
            check_daily_counts("16.TransferLogs/02, every account",
                               lambda: runner.run(billable_script, ["3"]), 3)
            if account:
                check_daily_counts("16.TransferLogs/02, account %s" % account,
                                   lambda: runner.run(billable_script, ["3", account]), 3, account)
        else:
            c.info("this server is older than %s, so transfers are not classified as "
                   "billable; the billable reports are not run" % BILLABLE_RELEASE)

    if st_client.server_release_at_least(client, BILLABLE_RELEASE):
        if runner.python_available():
            script = os.path.join(PY_TREE, "python3", "stBillableTransfers.py")
            with runner.real_credentials_python(PY_TREE, config):
                check_daily_counts("stBillableTransfers.py",
                                   lambda: runner.run_python(script, ["3"]), 3)
        else:
            c.info("no tests/local/pyvenv, so stBillableTransfers.py is not run. Create it with: "
                   "python3 -m venv tests/local/pyvenv && "
                   "tests/local/pyvenv/bin/pip install requests requests_toolbelt")

finally:
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own calls)"
       % client.calls)

sys.exit(c.done())
