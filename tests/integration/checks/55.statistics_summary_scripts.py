#!/usr/bin/env python3
"""
WRITES TO THE SERVER (an account, and four transfer log entries, which stay).
Runs the real, unmodified 33.StatisticsSummary examples, against what they report.

  01 (the report): a throwaway account, example_stat_user, uploads one tiny file to
     itself over the EndUser API and downloads it twice. After each step today's
     entry is read until it settles, and the script's own line for today is compared
     with the API's. The check shows what the numbers count: the upload moves
     TransfersIn and Transfers by one; the first download moves TransfersOut by one
     and Transfers by none (the first outbound of a file is free); the second moves
     both by one; deleting the file moves nothing. Also the date rules (dd/MM/yyyy
     only, the end day included, a future day refused) and a period against the sum
     of its days.
  02 (the active users): the account is not listed as logged in since the check began
     until it logs in; then the script finds it, with the time the API reports, by name
     (a part of the name, case sensitive, no wildcard) and by date.
  03 (the connection test): never sent to the real platform. The token address
     (StatisticsSummaryReport.Platform.Authentication) is pointed at a stand-in on this
     machine, which refuses; the script is run with and without a client id, the stand-in
     shows the form the server posted (the id and secret from the request, or the saved
     id), a 500 from it is relayed as 500, and a network zone is a 406 that sends nothing.
     The option is put back and compared. Needs st_callback_host.

The server's transfer log keeps the account's four entries (the upload, two downloads, the delete), and the active users list
keeps the account's name: neither can be removed. Needs --write and st_allow_writes="yes".
Refuses to start when example_stat_user exists. Counts of other transfers on the server
are read as they are, so a busy lab can make the exact-count checks fail: run it again.

It takes the date of the machine it runs on as the date of the server, so the two must be in
the same time zone; and it waits out midnight (st_client.avoid_midnight) so the day does not
change under it.
"""
import base64
import datetime
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import dummy_servers  # noqa: E402
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the statistics summary examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Statistics summary, run for real from Admin/API 2.0/bash/33.StatisticsSummary")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "33.StatisticsSummary")
USER = "example_stat_user"
PASSWORD = "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"
HOST = config["st_server"]
ENDUSER_PORT = config.get("st_enduser_port") or str(int(config["st_port"]) - 1)
CALLBACK = config.get("st_callback_host", "")
AUTH_OPTION = "StatisticsSummaryReport.Platform.Authentication"
CLIENT_OPTION = "StatisticsSummaryReport.ClientId"
FILE = "example_stat_%s.txt" % base64.b32encode(os.urandom(4)).decode().rstrip("=").lower()
KEYS = ("ST.TransfersIn", "ST.TransfersOut", "ST.Transfers")


def script(name, args=None, expect_rc=0, env=None):
    saved = {k: os.environ.get(k) for k in (env or {})}
    os.environ.update(env or {})
    try:
        result = runner.run(os.path.join(FOLDER, name), args, timeout=120)
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    out = result.stdout + result.stderr
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc, out.strip()[-300:])
    return out


def wait_for(predicate, seconds=30, every=2):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(every)
    return predicate()


def report(start, end=None, **flags):
    params = {"startDate": start, "endDate": end or start}
    params.update(flags)
    return admin.get("statisticsSummary/generateReport", params=params)


def today_string():
    return datetime.date.today().strftime("%d/%m/%Y")


def usage_today():
    response = report(today_string())
    days = response.json()["report"] if response.status == 200 else {}
    return {k: v for k, v in (list(days.values())[0]["usage"] if days else {}).items()}


def settled():
    """Today's usage once two reads, a few seconds apart, agree."""
    last = [None]

    def same():
        now = usage_today()
        ok = now == last[0] and now
        last[0] = now
        return ok
    wait_for(same, 40, 3)
    return last[0]


def counts(usage):
    return {k: usage.get(k, 0) for k in KEYS}


def delta(before, after):
    return {k: after[k] - before[k] for k in KEYS}


def after_step(before, expected, label):
    """Wait for today's counts to differ from `before` by exactly `expected`."""
    got = [None]

    def matches():
        got[0] = delta(before, counts(usage_today()))
        return got[0] == expected
    ok = wait_for(matches, 40, 3)
    c.check(label, ok, "expected %s, the server moved %s" % (expected, got[0]))
    return counts(settled())


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /statisticsSummary")
    admin.logout()
    sys.exit(c.done())
if admin.exists("accounts/" + USER):
    c.check("the account %s does not exist yet" % USER, False, "remove it first; this check will not touch it")
    admin.logout()
    sys.exit(c.done())

st_client.avoid_midnight()
saved_auth = admin.get("configurations/options/" + AUTH_OPTION).json()
enduser = None
try:
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        # --- the rules for the dates, and the shape of the answer
        out = script("01.statisticsSummary_generateReport_GET.sh")
        r = report(today_string())
        c.check("the API answers one day for today, one entry a day (granularity 86400000)", r.status == 200
                and len(r.json()["report"]) == 1 and r.json()["granularity"] == 86400000, r.text[:200])
        day = next(iter(r.json()["report"]))
        c.check("the entry is keyed by the start of the day, with the server's offset", day[:10] == datetime.date.today().isoformat()
                and day[10:].startswith("T00:00:00.000") and day[23:24] in "+-", day)
        c.check("01 with no argument reports today: %s" % day[:10], "  %s  in " % day[:10] in out and "Total: in " in out, out[-300:])
        yesterday = (datetime.date.today() - datetime.timedelta(days=1)).strftime("%d/%m/%Y")
        r = report(yesterday, today_string())
        c.check("the end day is included: yesterday to today is two entries", r.status == 200 and len(r.json()["report"]) == 2, r.text[:200])
        out = script("01.statisticsSummary_generateReport_GET.sh", [yesterday, today_string(), "true", "true"])
        days = r.json()["report"]
        c.check("01 prints a line for each of the two days, oldest first", out.index("  %s  in " % sorted(days)[0][:10]) <
                out.index("  %s  in " % sorted(days)[1][:10]), out[-400:])
        summary = r.json()["meta"]["reportSummary"]
        c.check("the report's total is the sum of its days (In, Out, Transfers)", all(
            summary[k] == sum(d["usage"][k] for d in days.values()) for k in KEYS), (summary, [d["usage"] for d in days.values()]))
        for label, params in (("no dates", {}), ("an ISO date", {"startDate": "2026-10-01", "endDate": "2026-10-02"}),
                              ("a start after the end", {"startDate": today_string(), "endDate": yesterday}),
                              ("a day that does not exist", {"startDate": "32/10/2026", "endDate": "33/10/2026"}),
                              ("tomorrow", {"startDate": today_string(), "endDate": (datetime.date.today() + datetime.timedelta(days=1)).strftime("%d/%m/%Y")})):
            r = admin.get("statisticsSummary/generateReport", params=params)
            c.check("the server refuses %s: 400" % label, r.status == 400 and r.json().get("validationErrors"), (r.status, r.text[:200]))
        r = report("01/01/2020", "03/01/2020")
        c.check("a period years back is three days of zeros", r.status == 200 and len(r.json()["report"]) == 3
                and all(sum(d["usage"].values()) == 0 for d in r.json()["report"].values()), r.text[:200])
        out = script("01.statisticsSummary_generateReport_GET.sh", [today_string(), yesterday], expect_rc=1)
        c.check("01 prints the server's reason for a start after the end", "HTTP 400" in out and "Incorrect date frame" in out, out[-300:])
        script("01.statisticsSummary_generateReport_GET.sh", ["2026-10-01"], expect_rc=2)
        script("01.statisticsSummary_generateReport_GET.sh", [today_string(), today_string(), "yes"], expect_rc=2)
        r = admin.head("statisticsSummary/generateReport")
        c.check("HEAD is 400 and a POST 405, GET of /operations 405", r.status == 400 and admin.post("statisticsSummary/generateReport", {}).status == 405
                and admin.get("statisticsSummary/operations").status == 405, r.status)

        # --- the account that makes the numbers move
        start_ms = int(time.time() * 1000) - 2000
        c.check("set up: the account %s" % USER, admin.post("accounts", {
            "name": USER, "type": "user", "uid": "1091", "gid": "1091", "homeFolder": "/home/" + USER,
            "user": {"name": USER, "passwordCredentials": {"password": PASSWORD}}}).status == 201)

        # 02, before the login
        def listed(args):
            out = script("02.statisticsSummary_activeUsers_GET.sh", args)
            return "  %s  " % USER in out, out
        found, out = listed([USER, str(start_ms)])
        c.check("02 does not list the account as logged in since the check began, before it logs in", not found, out[-300:])
        c.check("and it did not log in, so the API agrees", not admin.get("statisticsSummary/activeUsers", params={
            "name": USER, "lastAccessTime.from": str(start_ms)}).json()["result"])

        base = counts(settled())
        c.check("set up: today's counts have settled: %s" % base, bool(base))
        enduser = st_client.EndUserClient(HOST, ENDUSER_PORT, USER, PASSWORD)
        c.check("the account logs in to the EndUser API", enduser._request("POST", "myself", headers={
            "Authorization": "Basic " + enduser._auth}).status == 200)

        # 02, after the login
        c.check("02 lists the account once it has logged in (waits: the list is read again)",
                wait_for(lambda: listed([USER, str(start_ms)])[0], 30))
        api = admin.get("statisticsSummary/activeUsers", params={"name": USER, "lastAccessTime.from": str(start_ms)}).json()
        c.check("the API lists it once, with a login time as text and no ad hoc access", api["resultSet"]["totalCount"] == 1
                and api["result"][0]["name"] == USER and api["result"][0]["lastAccessTime"] and api["result"][0]["lastAdhocAccessTime"] == "", api)
        out = script("02.statisticsSummary_activeUsers_GET.sh", [USER, str(start_ms)])
        c.check("02 prints the line the API gives: user, last login, - for no ad hoc", "  %s  %s  -" % (USER, api["result"][0]["lastAccessTime"]) in out, out[-300:])
        c.check("02 by a part of the name: %s finds it" % USER[8:], listed([USER[8:]])[0])
        c.check("02 the name is case sensitive: %s finds nothing of ours" % USER.upper(), not listed([USER.upper()])[0])
        c.check("02 there is no wildcard: %s* finds nothing" % USER[:-3], not listed([USER[:-3] + "*"])[0])
        c.check("02 from a day ahead finds nothing, to the year 2000 finds nothing", not listed(["", str(start_ms + 86400000)])[0]
                and not listed([USER, "", "2000-01-01"])[0])
        out = script("02.statisticsSummary_activeUsers_GET.sh", ["", "not a date"], expect_rc=1)
        c.check("02 a bad date is refused with the server's reason", "HTTP 400" in out and "Invalid date format" in out, out[-300:])
        total = admin.get("statisticsSummary/activeUsers").json()["resultSet"]["totalCount"]
        out = script("02.statisticsSummary_activeUsers_GET.sh")
        c.check("02 with no filter prints all %d users the API counts" % total, "Users who have logged in: %d" % total in out
                and out.count("\n  ") == total, out[:120])
        c.check("a negative limit is 400, limit=0 lists everything", admin.get("statisticsSummary/activeUsers", params={"limit": -1}).status == 400
                and len(admin.get("statisticsSummary/activeUsers", params={"limit": 0}).json()["result"]) == total)

        # 01, against the numbers
        # the login did not move the counts
        c.check("a login moves no count", counts(settled()) == base, (base, counts(settled())))
        up = enduser.upload(FILE, b"x")
        c.check("an upload of one small file is 201", up.status == 201, up.status)
        base = after_step(base, {"ST.TransfersIn": 1, "ST.TransfersOut": 0, "ST.Transfers": 1}, "the upload moves In by 1, Transfers by 1, Out by 0")
        out = script("01.statisticsSummary_generateReport_GET.sh")
        now = usage_today()
        c.check("01 prints today's line as the API has it", "  %s  in %d  out %d  transfers %d  users %d  volume %d" % (
            datetime.date.today().isoformat(), now["ST.TransfersIn"], now["ST.TransfersOut"], now["ST.Transfers"],
            now["ST.ActiveUsers"], now["ST.Volume"]) in out, out[-300:])
        c.check("a download is 200", enduser.download(FILE).status == 200)
        base = after_step(base, {"ST.TransfersIn": 0, "ST.TransfersOut": 1, "ST.Transfers": 0},
                          "the first download moves Out by 1 and Transfers by 0 (the first outbound is free)")
        c.check("a second download is 200", enduser.download(FILE).status == 200)
        base = after_step(base, {"ST.TransfersIn": 0, "ST.TransfersOut": 1, "ST.Transfers": 1}, "the second download moves Out by 1 and Transfers by 1")
        c.check("the file is deleted: 204", enduser.delete_file(FILE).status == 204)
        time.sleep(10)
        c.check("a delete moves nothing (it is logged as outgoing, and not counted)", counts(settled()) == base, (base, counts(settled())))
        r = report(today_string(), today_string(), includeActiveUsersCount="true", includeIncomingFileVolume="true")
        c.check("the flags are accepted", r.status == 200, r.status)
        c.info("ST.ActiveUsers and ST.Volume on the lab: %s" % {k: v for k, v in usage_today().items() if k in ("ST.ActiveUsers", "ST.Volume")})

        # --- 03, against a stand-in for the platform's login
        if not CALLBACK:
            c.info("st_callback_host is not set: 03 is left out, it would reach the real platform")
        else:
            saved_client = admin.get("configurations/options/" + CLIENT_OPTION).json()["values"]
            with dummy_servers.FakeToken() as token:
                c.check("set up: the token address is the stand-in", admin.put("configurations/options", [
                    {"name": AUTH_OPTION, "values": ["http://%s:%d/token" % (CALLBACK, token.port)]}]).status == 204)
                out = script("03.statisticsSummary_operations_POST_testConnection.sh", ["example_client"], expect_rc=1,
                             env={"AMPLIFY_CLIENT_SECRET": "example_secret"})
                c.check("03 shows the platform's refusal, relayed with its own status", "HTTP 401" in out
                        and "The platform answered: invalid_client: Invalid client" in out, out[-300:])
                c.check("the stand-in was asked once, for a client credentials token, with the id and the secret of the request",
                        len(token.requests) == 1 and token.form() == {"grant_type": "client_credentials", "client_id": "example_client",
                                                                       "client_secret": "example_secret"}, token.requests and token.requests[-1]["body"])
                script("03.statisticsSummary_operations_POST_testConnection.sh", expect_rc=1)
                c.check("with no argument the saved client id is used", len(token.requests) == 2 and token.form()["client_id"] == saved_client[0],
                        (saved_client, token.requests[-1]["body"]))
                token.status, token.answer = 500, {"error": "boom", "error_description": "broken"}
                out = script("03.statisticsSummary_operations_POST_testConnection.sh", ["example_client"], expect_rc=1)
                c.check("a 500 from the platform is a 500 from the server, with the platform's body", "HTTP 500" in out
                        and "The platform answered: boom: broken" in out, out[-300:])
                seen = len(token.requests)
                out = script("03.statisticsSummary_operations_POST_testConnection.sh", ["example_client", "example_zone"], expect_rc=1)
                c.check("a network zone is a 406 and the stand-in is not asked", "HTTP 406" in out and "Test connection to the Amplify Platform failed" in out
                        and len(token.requests) == seen, out[-300:])
                script("03.statisticsSummary_operations_POST_testConnection.sh", ["a", "b", "c", "d"], expect_rc=2)
                r = admin.post("statisticsSummary/operations", {}, params={"operation": "testConnection"})
                c.check("a body with no type is 406 too, and the stand-in is not asked", r.status == 406 and len(token.requests) == seen, (r.status, r.text[:150]))
                r = admin.post("statisticsSummary/operations", {"type": "testConnection"})
                c.check("no operation is 400", r.status == 400 and "Valid operation is: testConnection" in r.text, (r.status, r.text[:150]))
            admin.put("configurations/options", [{"name": AUTH_OPTION, "values": saved_auth["values"]}])
            c.check("the token address is back as it was", admin.get("configurations/options/" + AUTH_OPTION).json() == saved_auth)
finally:
    if enduser is not None:
        try:
            enduser.delete_file(FILE)
            enduser.logout()
        except Exception:
            pass
    now_auth = admin.get("configurations/options/" + AUTH_OPTION).json()
    if now_auth != saved_auth:
        admin.put("configurations/options", [{"name": AUTH_OPTION, "values": saved_auth["values"]}])
    admin.delete("accounts/" + USER)
    c.check("nothing is left behind: no account, the token address as it was",
            not admin.exists("accounts/" + USER) and admin.get("configurations/options/" + AUTH_OPTION).json() == saved_auth)
    admin.logout()

sys.exit(c.done())
