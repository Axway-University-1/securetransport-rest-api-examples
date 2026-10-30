#!/usr/bin/env python3
"""
WRITES TO THE SERVER (three business units, six accounts and 100 uploads, all named or made as example_use_*, which it removes; the 100 transfers
stay in the transfer log, as no call deletes a log entry). Runs Admin/UseCases/07-usage-reporting for real, as the administrator of the configuration.

It proves what the use case and its README say, through its own calls and not through the scripts:
  - part 1: the usage report settings are there and a secret is not printed; the active users list is a page of 100 and holds every name with limit=1000, and the
    name filter looks inside the name; generateReport has the structure the README shows, the summary is the sum of its days, the four refusals are 400 with their
    messages, and a businessUnit parameter changes nothing; the transfer log counts with totalCount, account= is a filter and accountName= is not, isBillable has
    true and false;
  - part 2: the accounts of a unit are the ones made for it; 100 uploads (25 and 15, 20 and 15, 15 and 10) are in the log as 40, 35 and 25 transfers of the
    three units, all inbound and all billable, and the same for each account; the report says at least 100 more than before; the unit filter of the log is 404 for a
    unit that does not exist, and the account list is 200 and empty; the table of 11 has the same numbers and the shares; the active users of a unit are the names of its
    accounts that the list holds; after the cleanup a deleted unit is no longer found in the log and its accounts still are.
Then it runs the scripts and compares what they printed with what it read, and runs 00.run_all.sh once more as a whole.

Needs --write and st_allow_writes="yes". Takes about 4 minutes (two times 100 uploads): run it with ST_CHECK_TIMEOUT=600. It does not run on the bundled mock.
"""
import datetime
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the usage reporting use case for real")

c = st_client.Checker("Admin use case 07-usage-reporting, run for real")

UC = runner.path("Admin", "UseCases", "07-usage-reporting")
ENV = {"ST_ENDUSER_PORT": harness.ports(config).enduser}
STATE_FILES = ("session.cookie.jar", "state.local.csrf", "state.local.password", "state.local.window", "state.local.report")
UNITS = ["example_use_bu1", "example_use_bu2", "example_use_bu3"]
ACCOUNTS = {"example_use_a1": ("example_use_bu1", 25), "example_use_b1": ("example_use_bu1", 15), "example_use_c1": ("example_use_bu2", 20),
            "example_use_d1": ("example_use_bu2", 15), "example_use_e1": ("example_use_bu3", 15), "example_use_f1": ("example_use_bu3", 10)}
UNIT_UPLOADS = {"example_use_bu1": 40, "example_use_bu2": 35, "example_use_bu3": 25}

admin = harness.connect(config, c, mock="the bundled mock has no business units or transfer log; run this against a real server to exercise it")


def clear_local():
    for leftover in STATE_FILES:
        p = os.path.join(UC, leftover)
        if os.path.exists(p):
            os.remove(p)


def script(name, *args, timeout=400):
    return runner.run(os.path.join(UC, name), list(args), timeout=timeout, env=ENV)


def total(path, params=None):
    return (admin.get(path, dict(params or {}, limit=1, fields="id" if path.startswith("logs") else "name")).json() or {}).get("resultSet", {}).get("totalCount")


def report(start, end, **extra):
    response = admin.get("statisticsSummary/generateReport", dict({"startDate": start, "endDate": end}, **extra))
    return response, (response.json() or {}) if response.status == 200 else {}


def leftovers():
    return [a for a in ACCOUNTS if admin.exists("accounts/" + a)] + [u for u in UNITS if admin.exists("businessUnits/" + u)]


def table_rows(text):
    """The rows of the table of 11: {name: (accounts, transfers, billable, share)}."""
    rows = {}
    for m in re.finditer(r"^  (.+?)\s{2,}(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+%|-)$", text, re.M):
        rows[m.group(1).strip()] = (int(m.group(2)), int(m.group(3)), int(m.group(4)), m.group(5))
    return rows


try:
    if leftovers():
        c.info("objects named example_use_* are on the server already (%s); skipping rather than reuse them" % ", ".join(leftovers()))
        admin.logout()
        sys.exit(c.done())

    # ================= part 1: the whole server ==================================================================================
    r = script("01.settings_GET.sh")
    options = admin.results("configurations/options", {"name": "StatisticsSummaryReport*", "limit": 100})
    names = sorted(o["name"] for o in options)
    secret = next((o["values"][0] for o in options if "Secret" in o["name"] and o.get("values")), None)
    c.check("01: exit 0, and every StatisticsSummaryReport* setting of the server is printed by name", r.returncode == 0 and names and all(n in r.stdout for n in names), (r.returncode, r.stdout[-300:]))
    c.check("01: the secret is not printed, and is said to be hidden", r.returncode == 0 and (not secret or secret not in r.stdout) and "ClientSecret = (hidden)" in r.stdout, r.stdout[-300:])
    version = (admin.get("version").json() or {}).get("version")
    c.check("01: the release is the one /version gives", version and "Release %s" % version in r.stdout, (version, r.stdout[:200]))

    r = script("02.activeUsers_GET.sh")
    page = admin.get("statisticsSummary/activeUsers").json()["resultSet"]
    whole = admin.get("statisticsSummary/activeUsers", {"limit": 1000}).json()
    c.check("02: a page is 100 names (or the whole list when it is shorter), and limit=1000 returns every name",
            page["returnCount"] == min(100, page["totalCount"]) and (page["totalCount"] > 1000 or whole["resultSet"]["returnCount"] == whole["resultSet"]["totalCount"]), (page, whole["resultSet"]))
    account_names = {a["name"] for a in admin.results("accounts", {"limit": 1000, "fields": "name"})}
    gone = len({e["name"] for e in whole["result"]} - account_names)
    c.check("02: exit 0, with the number of names that are no longer an account, as counted here (%d)" % gone, r.returncode == 0 and "%d are no longer an account" % gone in r.stdout, (gone, r.stdout[:500]))
    first = whole["result"][0]["name"] if whole["result"] else ""
    if len(first) > 2:
        middle = first[1:-1]
        inside = (admin.get("statisticsSummary/activeUsers", {"name": middle, "limit": 1}).json() or {}).get("resultSet", {}).get("totalCount")
        c.check("02: the name filter looks inside the name ('%s' inside '%s' finds %s)" % (middle, first, inside), inside and inside >= 1)
    star = (admin.get("statisticsSummary/activeUsers", {"name": "*", "limit": 1}).json() or {}).get("resultSet", {}).get("totalCount")
    c.check("02: * is not a wildcard in the name filter (name=* finds %s, and the same filter on accounts finds %s)" % (star, total("accounts", {"name": "*"})), star == 0 and total("accounts", {"name": "*"}) > 0)

    # the report: two past days, structure and sums
    start, end = "25/10/2026", "26/10/2026"
    response, answer = report(start, end)
    days = sorted((answer.get("report") or {}))
    c.check("report: 200 with one entry for each day, named by the start of the day with its offset, granularity one day",
            response.status == 200 and len(days) == 2 and all(re.match(r"^2026-10-2[56]T00:00:00\.000[+-]\d\d:\d\d$", d) for d in days) and answer.get("granularity") == 86400000, (response.status, days))
    summary = answer.get("meta", {}).get("reportSummary", {})
    c.check("report: the summary is the sum of the days, for transfers, in and out",
            all(sum(d["usage"][k] for d in answer["report"].values()) == summary.get(k) for k in ("ST.Transfers", "ST.TransfersIn", "ST.TransfersOut")), summary)
    c.check("report: the time frame ends at the start of the day after the last day", (answer.get("meta", {}).get("reportTimeframe") or {}).get("endDate", "").startswith("2026-10-27T00:00:00"))
    r = script("03.generateReport_GET.sh", start, end)
    c.check("03: exit 0, and the summary it prints is the one read here (%s)" % summary.get("ST.Transfers"),
            r.returncode == 0 and "Summary: transfers %s, in %s, out %s" % (summary.get("ST.Transfers"), summary.get("ST.TransfersIn"), summary.get("ST.TransfersOut")) in r.stdout, (r.returncode, r.stdout[-500:]))
    c.check("03: the four refusals are shown", r.stdout.count("Refused, as it should be") == 4, r.stdout[-700:])
    for label, params, text in (("no endDate", {"startDate": start}, "'startDate' and 'endDate' parameters are mandatory."),
                                ("startDate after endDate", {"startDate": "26/10/2026", "endDate": "25/10/2026"}, "Incorrect date frame. 'startDate' must be before 'endDate'."),
                                ("yyyy-MM-dd", {"startDate": "2026-10-23", "endDate": "2026-10-24"}, "is not in correct format. The correct format is: dd/MM/yyyy."),
                                ("a day in the future", {"startDate": "01/01/2030", "endDate": "02/01/2030"}, "An error occur while generating report")):
        response = admin.get("statisticsSummary/generateReport", params)
        c.check("report refuses %s with 400 and its message" % label, response.status == 400 and text in response.text, (response.status, response.text[:200]))
    one, whole_one = report(start, start)
    c.check("report: the same day for both dates gives one entry, and a day with no leading zero is accepted",
            one.status == 200 and len(whole_one.get("report", {})) == 1 and report("5/10/2026", "5/10/2026")[0].status == 200)
    before_bu = report("01/10/2026", "02/10/2026")[1].get("meta", {}).get("reportSummary", {})
    with_bu = report("01/10/2026", "02/10/2026", businessUnit="no_such_unit_at_all")
    c.check("report: a businessUnit parameter is ignored without a word (200, and the same summary as without it)", with_bu[0].status == 200 and with_bu[1].get("meta", {}).get("reportSummary") == before_bu, (with_bu[0].status, with_bu[0].text[:120]))
    active_all = total("statisticsSummary/activeUsers")
    c.check("activeUsers: a businessUnit parameter is ignored too (same totalCount)", (admin.get("statisticsSummary/activeUsers", {"businessUnit": "no_such_unit_at_all", "limit": 1}).json() or {}).get("resultSet", {}).get("totalCount") == active_all)

    # the log: totalCount, the three filters
    now_total = total("logs/transfers")
    c.check("log: accountName=nosuch answers the whole log (the filter does not exist), and account=nosuch answers 0",
            total("logs/transfers", {"accountName": "example_use_no_such_account"}) in (now_total, now_total + 1) and total("logs/transfers", {"account": "example_use_no_such_account"}) == 0)
    billable_true = total("logs/transfers", {"isBillable": "true"})
    billable_false = total("logs/transfers", {"isBillable": "false"})
    c.check("log: isBillable=true and isBillable=false both count, and their sum is not more than the log (%s + %s of %s)" % (billable_true, billable_false, now_total),
            billable_true is not None and billable_false is not None and billable_true + billable_false <= total("logs/transfers"))
    r = script("04.transfers_billable_count_GET.sh", "2")
    rows = re.findall(r"^  ([A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} 00:00:00 [+-]\d{4})  (\d+)$", r.stdout, re.M)
    c.check("04: exit 0 with one line for each of the two days", r.returncode == 0 and len(rows) == 2, (r.returncode, r.stdout[-500:]))
    if len(rows) == 2:
        (s1, n1), (s2, n2) = rows
        read_first = total("logs/transfers", {"isBillable": "true", "startTimeAfter": s1, "endTimeBefore": s2})
        read_second = total("logs/transfers", {"isBillable": "true", "startTimeAfter": s2})
        c.check("04: the first day is the count read here for the same window (%s)" % read_first, int(n1) == read_first, (n1, read_first))
        c.check("04: the second day is at least that of the same window read here (%s, others may add transfers while it runs)" % read_second, read_second <= int(n2) <= read_second + 50, (n2, read_second))
    c.check("04: it prints the three values of isBillable and says accountName= is not a filter", "with no value (in neither count)" in r.stdout and "accountName is not a filter" in r.stdout and "account is the filter." in r.stdout, r.stdout[-600:])
    r = script("05.report_vs_log.sh", "2")
    c.check("05: exit 0, two rows and the sentence about the invoice", r.returncode == 0 and len(re.findall(r"^\d{2}/\d{2}/\d{4} ", r.stdout, re.M)) == 2 and "from the report" in r.stdout, (r.returncode, r.stdout[-400:]))

    # ================= part 2: the business units =================================================================================
    r = script("06.business_units_POST.sh")
    c.check("06: exit 0", r.returncode == 0, (r.stdout + r.stderr)[-500:])
    c.check("06: the three units are there", all(admin.exists("businessUnits/" + u) for u in UNITS))
    made = {}
    for name, (unit, uploads) in ACCOUNTS.items():
        response = admin.get("accounts/" + name)
        body = response.json() if response.status == 200 else {}
        made[name] = body
    c.check("06: the six accounts are there, each in its unit, with its home folder under the unit",
            all(made[n].get("businessUnit") == u and made[n].get("homeFolder") == "/home/%s/%s" % (u, n) for n, (u, _) in ACCOUNTS.items()), {n: (b.get("businessUnit"), b.get("homeFolder")) for n, b in made.items()})
    c.check("06: the two accounts of a unit share the unit's group, and have their own user id",
            made["example_use_a1"].get("gid") == made["example_use_b1"].get("gid") and made["example_use_a1"].get("uid") != made["example_use_b1"].get("uid"))
    c.check("06: the accounts of a unit, from the list with the filter", all(sorted(a["name"] for a in admin.results("accounts", {"businessUnit": u, "limit": 100})) == sorted(n for n, (uu, _) in ACCOUNTS.items() if uu == u) for u in UNITS))
    password = open(os.path.join(UC, "state.local.password")).read() if os.path.exists(os.path.join(UC, "state.local.password")) else ""
    c.check("06: the password is kept, and only the owner can read the file", len(password) > 8 and (os.stat(os.path.join(UC, "state.local.password")).st_mode & 0o077) == 0)
    r = script("06.business_units_POST.sh")
    c.check("06 again, with the objects there: exit 1, and nothing more is created", r.returncode == 1 and "exists already" in r.stdout and len(admin.results("accounts", {"businessUnit": "example_use_bu1"})) == 2, (r.returncode, r.stdout[-300:]))

    report_before = report(*[datetime.datetime.now().strftime("%d/%m/%Y")] * 2)[1].get("meta", {}).get("reportSummary", {}).get("ST.Transfers")
    r = script("07.transfers_make_POST.sh")
    c.check("07: exit 0, and the log shows 40, 35 and 25", r.returncode == 0 and "The log shows: example_use_bu1=40 example_use_bu2=35 example_use_bu3=25." in r.stdout, (r.returncode, r.stdout[-500:]))
    window = open(os.path.join(UC, "state.local.window")).read().strip()
    kept = open(os.path.join(UC, "state.local.report")).read().split()
    c.check("07: it kept a window in RFC 2822 and the report of the day before the uploads (not more than what the report says now)",
            re.match(r"^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} [+-]\d{4}$", window) and len(kept) == 2 and abs(int(kept[1]) - report_before) <= 20, (window, kept, report_before))

    # the log, independently
    def log_total(extra):
        return total("logs/transfers", dict({"startTimeAfter": window}, **extra))
    c.check("log: each unit has its number of transfers, all billable, all inbound",
            all(log_total({"businessUnit": u}) == n and log_total({"businessUnit": u, "isBillable": "true"}) == n and log_total({"businessUnit": u, "incoming": "true"}) == n for u, n in UNIT_UPLOADS.items()),
            {u: (log_total({"businessUnit": u}), log_total({"businessUnit": u, "isBillable": "true"})) for u in UNITS})
    c.check("log: each account has its number of transfers, by account=",
            all(log_total({"account": a}) == n and log_total({"account": a, "isBillable": "true"}) == n for a, (_, n) in ACCOUNTS.items()), {a: log_total({"account": a}) for a in ACCOUNTS})
    c.check("log: the three units add up to 100, and the whole server has at least 100 billable transfers in the window",
            sum(log_total({"businessUnit": u, "isBillable": "true"}) for u in UNITS) == 100 and log_total({"isBillable": "true"}) >= 100)
    c.check("log: a unit that does not exist is 404 in the log and 200 with nothing in the account list",
            admin.get("logs/transfers", {"businessUnit": "example_use_nosuch", "limit": 1}).status == 404 and total("accounts", {"businessUnit": "example_use_nosuch"}) == 0)
    c.check("log: with no filter on time the first unit holds at least its 40 transfers", total("logs/transfers", {"businessUnit": "example_use_bu1"}) >= 40)

    r = script("08.global_total_GET.sh")
    server_billable = log_total({"isBillable": "true"})
    report_after = report(*[datetime.datetime.now().strftime("%d/%m/%Y")] * 2)[1].get("meta", {}).get("reportSummary", {}).get("ST.Transfers")
    m = re.search(r"is (\d+) now: (\d+) more\.", r.stdout)
    c.check("08: exit 0, the log says the billable transfers of the window (at least 100, about %s)" % server_billable, r.returncode == 0 and re.search(r"(\d+) billable transfers\.", r.stdout) and int(re.search(r"(\d+) billable transfers\.", r.stdout).group(1)) >= 100, r.stdout[-500:])
    c.check("08: the report says at least 100 more than before the uploads (%s more by the read here)" % (report_after - int(kept[1]) if report_after is not None else "?"),
            m and int(m.group(2)) >= 100 and int(m.group(1)) - int(kept[1]) == int(m.group(2)) and int(m.group(1)) <= report_after, (m and m.groups(), report_after, kept))
    c.check("08: it shows that the report ignores a business unit", "generateReport with businessUnit=example_use_bu1: HTTP 200" in r.stdout and "that parameter is ignored" in r.stdout, r.stdout[-400:])

    r = script("09.business_unit_accounts_GET.sh", "example_use_bu1")
    c.check("09: exit 0, the two accounts of the first unit, and what the log knows of it (at least 40)",
            r.returncode == 0 and "has 2 accounts:" in r.stdout and "example_use_a1  businessUnit example_use_bu1" in r.stdout and "example_use_b1  businessUnit example_use_bu1" in r.stdout and "The transfer log knows the unit:" in r.stdout, r.stdout[-500:])
    r = script("09.business_unit_accounts_GET.sh", "example_use_nosuch")
    c.check("09: a unit that does not exist is exit 0, with the 404 of the log and the warning about the empty list",
            r.returncode == 0 and "HTTP 404, Cannot find business unit with name example_use_nosuch." in r.stdout and "does not prove that the unit is there" in r.stdout, r.stdout[-500:])

    active_names = {e["name"] for e in admin.get("statisticsSummary/activeUsers", {"limit": 1000}).json().get("result", [])}
    for unit, uploads in UNIT_UPLOADS.items():
        r = script("10.usage_per_business_unit_GET.sh", unit)
        members = [a for a, (u, _) in ACCOUNTS.items() if u == unit]
        active = len([a for a in members if a in active_names])
        c.check("10 %s: exit 0, %d transfers, %d billable, %d incoming, the accounts add up, and %d of its accounts are in the active users list as read here" % (unit, uploads, uploads, uploads, active),
                r.returncode == 0 and "Business unit %s: 2 accounts, %d transfers, %d billable (%d incoming), %d active users." % (unit, uploads, uploads, uploads, active) in r.stdout and "The accounts add up to the unit." in r.stdout, (r.returncode, r.stdout[-500:]))
        for a in members:
            c.check("10 %s: the line of %s says %d transfers" % (unit, a, ACCOUNTS[a][1]), "  %s: %d transfers, %d billable" % (a, ACCOUNTS[a][1], ACCOUNTS[a][1]) in r.stdout, r.stdout[-400:])
    r = script("10.usage_per_business_unit_GET.sh", "example_use_nosuch")
    c.check("10: a unit the log does not know is exit 1, with the reason", r.returncode == 1 and "Cannot find business unit with name example_use_nosuch." in r.stdout, (r.returncode, r.stdout[-300:]))

    r = script("11.usage_all_business_units_GET.sh")
    rows = table_rows(r.stdout)
    server_accounts = total("accounts")
    server_all = log_total({})  # noqa: F841
    server_billable = log_total({"isBillable": "true"})
    c.check("11: exit 0, with a row for each of the three units, its accounts, transfers, billable and share of the server's billable transfers",
            r.returncode == 0 and all(rows.get(u, (None,))[:3] == (2, n, n) for u, n in UNIT_UPLOADS.items()), (r.returncode, rows))
    c.check("11: the share of a unit is its billable transfers over the server's, to one decimal (%s billable on the server)" % server_billable,
            all(u in rows and abs(float(rows[u][3].rstrip("%")) - 100.0 * n / server_billable) <= 1.0 for u, n in UNIT_UPLOADS.items()), (rows, server_billable))
    c.check("11: all the units add up to 6 accounts and 100 transfers, billable and in all", rows.get("all the units", (None,))[:3] == (6, 100, 100), rows.get("all the units"))
    c.check("11: the whole server has the accounts counted here (%d), and what is in no unit is the difference between the server and the units" % server_accounts,
            rows.get("the whole server", (0, 0, 0))[0] == server_accounts and rows.get("in no business unit", (-1,))[0] == server_accounts - rows.get("all the units", (0,))[0]
            and rows.get("in no business unit", (0, 0, 0))[2] >= 0 and rows.get("the whole server", (0, 0, 0))[2] >= 100, rows)
    c.check("11: the line below the table says what is in no unit, or that every transfer belongs to a unit", "The units add up to" in r.stdout, r.stdout[-300:])

    r = script("99.cleanup_DELETE.sh")
    c.check("99: exit 0, and nothing named example_use_* is left (accounts or units)", r.returncode == 0 and leftovers() == [], (r.returncode, leftovers(), r.stdout[-400:]))
    c.check("99: the log no longer finds the deleted unit (404), and still finds the accounts' transfers by account=",
            admin.get("logs/transfers", {"businessUnit": "example_use_bu1", "limit": 1}).status == 404 and total("logs/transfers", {"account": "example_use_a1", "isBillable": "true", "startTimeAfter": window}) == 25,
            (admin.get("logs/transfers", {"businessUnit": "example_use_bu1", "limit": 1}).status, total("logs/transfers", {"account": "example_use_a1", "isBillable": "true", "startTimeAfter": window})))
    c.check("99: the cleanup, which empties the home folders through the End User API, adds outgoing transfers that are not billable (the 25 deletes of a1 are in the log)",
            total("logs/transfers", {"account": "example_use_a1", "startTimeAfter": window}) >= 25 and total("logs/transfers", {"account": "example_use_a1", "isBillable": "false", "startTimeAfter": window}) >= 25)
    for leftover in STATE_FILES:
        c.check("99: no %s is left" % leftover, not os.path.exists(os.path.join(UC, leftover)))
    r = script("99.cleanup_DELETE.sh")
    c.check("99 a second time, with nothing to remove, exits 0", r.returncode == 0, r.stdout[-300:])

    # ================= the whole use case, once more ==============================================================================
    r = script("00.run_all.sh", "2", timeout=500)
    c.check("00: exit 0, 11 steps and the cleanup", r.returncode == 0 and r.stdout.count("=== ") >= 12 and "=== 99.cleanup_DELETE ===" in r.stdout, (r.returncode, r.stdout[-600:]))
    final = table_rows(r.stdout.split("=== 11.usage_all_business_units_GET ===")[-1])
    c.check("00: the table of the whole run has the 40, 35 and 25 and the sum of 100", all(final.get(u, (None,))[:3] == (2, n, n) for u, n in UNIT_UPLOADS.items()) and final.get("all the units", (None,))[:3] == (6, 100, 100), final)
    c.check("00: and it left nothing behind", leftovers() == [] and not any(os.path.exists(os.path.join(UC, f)) for f in STATE_FILES), leftovers())
    r = script("00.run_all.sh", "0")
    c.check("00: a wrong DAYS is exit 2 and nothing is made", r.returncode == 2 and leftovers() == [], (r.returncode, r.stdout[-200:]))
finally:
    for name in ACCOUNTS:
        if admin.exists("accounts/" + name):
            admin.delete("accounts/" + name)
    for name in UNITS:
        if admin.exists("businessUnits/" + name):
            admin.delete("businessUnits/" + name)
    c.check("no account or business unit named example_use_* is left on the server", leftovers() == [], leftovers())
    clear_local()
    admin.logout()

sys.exit(c.done())
