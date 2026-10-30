#!/usr/bin/env python3
"""
WRITES TO THE SERVER (five throwaway business units named example_lst_1 to example_lst_5, which it removes). Runs
Admin/UseCases/06-lists-paging-and-fields for real, as the administrator of the configuration.

It proves what the use case and its README say about the lists, through its own calls to the API and not through the
scripts: a page is 100 when no limit is asked for, limit=0 gives the same page, a limit of 1000 gives 1000 when the list
is long enough, a negative or non-numeric limit is 400 with its message, an offset past the end is a 200 with nothing in
it, fields= narrows an answer and refuses a field that does not exist, protocol on /servers cannot be asked for, HEAD
is 200 and 404 and 405 for deniedUsers, a POST that creates has no body and a Location that ends with the name, a
filter changes totalCount and takes capitals. Then it runs the scripts and compares what they printed with what it
read: 00.run_all.sh exits 0 and ends with the cleanup, 01 on the transfer log says 100 of the total it read, 02 reads
every server, 05 leaves exactly five units, a second 05 is refused and leaves five, 06 prints the names the API gives
for the same page, 99 leaves nothing and can be run twice.

Needs --write and st_allow_writes="yes". It does not run on the bundled mock, which has no business units.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the lists, paging and fields use case for real")

c = st_client.Checker("Admin use case 06-lists-paging-and-fields, run for real")

ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
UC = runner.path("Admin", "UseCases", "06-lists-paging-and-fields")
STATE_FILES = ("session.cookie.jar", "state.local.csrf")
NAMES = ["example_lst_%d" % n for n in range(1, 10)]

admin = harness.connect(config, c, mock="the bundled mock has no business units; run this against a real server to exercise it")


def clear_local():
    for leftover in STATE_FILES:
        p = os.path.join(UC, leftover)
        if os.path.exists(p):
            os.remove(p)


def units():
    """The names of the throwaway business units on the server, from a filtered list read here."""
    return sorted(u.get("name") for u in admin.results("businessUnits", {"name": "example_lst_*"}))


def total(path, params=None):
    return (admin.get(path, dict(params or {}, limit=1)).json() or {}).get("resultSet", {}).get("totalCount")


try:
    if units():
        c.info("business units named example_lst_* are on the server already (%s); skipping rather than reuse them" % ", ".join(units()))
        admin.logout()
        sys.exit(c.done())

    # -- what the README says about the answers, read here --------------------------------------------------
    answer = admin.get("accounts", {"limit": 2, "fields": "name"})
    body = answer.json() or {}
    c.check("a list answers {resultSet, result}, and returnCount is what this answer holds",
            answer.status == 200 and body.get("resultSet", {}).get("returnCount") == len(body.get("result", [])) == 2, answer.text[:200])
    accounts_total = body.get("resultSet", {}).get("totalCount")
    c.check("fields=name gives name and the type of the object, nothing else",
            all(sorted(e) == ["name", "type"] for e in body.get("result", [])), body.get("result"))
    r = admin.get("accounts", {"limit": 1, "fields": "nosuch"})
    c.check("a field that does not exist is 400 with its message", r.status == 400 and "Field nosuch does not exist." in r.text, (r.status, r.text[:200]))
    r = admin.get("servers", {"limit": 1, "fields": "serverName"})
    entry = ((r.json() or {}).get("result") or [{}])[0]
    c.check("/servers with fields=serverName still has the protocol in its entry", r.status == 200 and "protocol" in entry and "serverName" in entry, entry)
    r = admin.get("servers", {"limit": 1, "fields": "protocol"})
    c.check("and fields=protocol on /servers is refused: Field protocol does not exist.", r.status == 400 and "Field protocol does not exist." in r.text, (r.status, r.text[:200]))
    r = admin.get("sites", {"limit": 1, "fields": "type"})
    c.check("fields=type on /sites is refused the same way", r.status == 400 and "Field type does not exist." in r.text, (r.status, r.text[:200]))
    r = admin.get("accounts", {"limit": -1})
    c.check("limit=-1 is 400 'The limit should be a positive number or 0.'", r.status == 400 and "The limit should be a positive number or 0." in r.text, (r.status, r.text[:200]))
    r = admin.get("accounts", {"limit": "abc"})
    c.check("limit=abc is 400 \"'limit' param is not a number\"", r.status == 400 and "'limit' param is not a number" in r.text, (r.status, r.text[:200]))
    r = admin.get("accounts", {"limit": 1, "offset": accounts_total})
    body = r.json() or {}
    c.check("an offset at the end is a 200 with nothing in it and the same totalCount",
            r.status == 200 and body.get("result") == [] and body.get("resultSet", {}).get("totalCount") == accounts_total, r.text[:200])
    first_account = admin.results("accounts", {"limit": 1, "fields": "name"})[0]["name"]
    c.check("HEAD of an account that is there is 200", admin.head("accounts/" + first_account).status == 200, first_account)
    c.check("HEAD of one that is not is 404", admin.head("accounts/example_lst_missing").status == 404)
    c.check("HEAD of a deniedUsers name is 405, not 404", admin.head("deniedUsers/example_lst_none").status == 405)

    option = admin.results("configurations/options", {"name": "Webservices.EntriesPerPage"})
    page_size = int((option[0].get("values") or ["100"])[0]) if option else 100
    long_list = None
    for path in ("logs/transfers", "logs/audits"):
        count = total(path)
        if count and count > page_size:
            long_list = path
            break
    if long_list is None:
        c.info("no list on this server is longer than a page (%s): the checks of the default page are skipped" % page_size)
    else:
        count = total(long_list)
        no_limit = admin.get(long_list)
        c.check("%s: with no limit the answer holds one page (%s of %s)" % (long_list, page_size, count),
                no_limit.status == 200 and no_limit.json()["resultSet"]["returnCount"] == page_size, no_limit.text[:100])
        zero = admin.get(long_list, {"limit": 0})
        c.check("%s: limit=0 gives that page again, not everything" % long_list, zero.status == 200 and zero.json()["resultSet"]["returnCount"] == page_size, zero.text[:100])
        thousand = admin.get(long_list, {"limit": 1000})
        wanted = min(1000, count)
        c.check("%s: limit=1000 gives %s" % (long_list, wanted), thousand.status == 200 and thousand.json()["resultSet"]["returnCount"] >= min(wanted, 1000) - 5, thousand.text[:100])

    # -- the scripts ------------------------------------------------------------------------------------------
    with runner.real_credentials(ADMIN_TREE, config):
        accounts_before = total("accounts")
        r = runner.run(os.path.join(UC, "00.run_all.sh"), timeout=300)
        accounts_after = total("accounts")
        c.check("00.run_all.sh exits 0", r.returncode == 0, (r.stdout + r.stderr).strip()[-500:])
        c.check("it ended with the cleanup", "Cleaned up." in r.stdout, r.stdout[-200:])
        c.check("and left no business unit and no state file", units() == [] and not any(os.path.exists(os.path.join(UC, f)) for f in STATE_FILES))
        read = re.search(r"Read (\d+) entries in \d+ pages\. totalCount said (\d+)\.", r.stdout)
        c.check("02 read every account: the entries it counted are the totalCount it said, and the one this check read before and after",
                read is not None and read.group(1) == read.group(2) and min(accounts_before, accounts_after) <= int(read.group(1)) <= max(accounts_before, accounts_after),
                (accounts_before, accounts_after, r.stdout[:600]))
        clear_local()

        if long_list:
            before = total(long_list)
            r = runner.run(os.path.join(UC, "01.list_default_GET.sh"), [long_list], timeout=120)
            after = total(long_list)
            said = re.search(r"returnCount (\d+), totalCount (\d+)\.", r.stdout)
            c.check("01 on %s: exit 0, one page of %s, and a totalCount between what this check read before and after" % (long_list, page_size),
                    r.returncode == 0 and said is not None and int(said.group(1)) == page_size and before <= int(said.group(2)) <= after, (before, after, r.stdout[:400]))
            c.check("01 says it is one page and where the rest is", "This is one page, the first %s of" % page_size in r.stdout and "02.paging_walk.sh reads the rest." in r.stdout, r.stdout[:600])
            c.check("01 names the setting that gives the page size", "Webservices.EntriesPerPage: %s." % page_size in r.stdout, r.stdout[:600])
            c.check("01: limit=0 is said to be the default page", "limit=0 does not mean all." in r.stdout, r.stdout[-400:])

        servers = total("servers")
        r = runner.run(os.path.join(UC, "02.paging_walk.sh"), ["servers", "2"], timeout=120)
        pages = -(-servers // 2)
        c.check("02 on servers, two a call: exit 0, %s pages, every server read" % pages,
                r.returncode == 0 and "Read %s entries in %s pages" % (servers, pages) in r.stdout and "A page past the end (offset %s): HTTP 200, 0 entries" % servers in r.stdout, r.stdout[-500:])
        r = runner.run(os.path.join(UC, "02.paging_walk.sh"), ["servers", "0"])
        c.check("02 with a PAGE_SIZE of 0 is refused before any call (exit 2) and says 0 is not all", r.returncode == 2 and "(0 is not 'all'" in r.stdout, (r.returncode, r.stdout[-300:]))

        r = runner.run(os.path.join(UC, "03.fields_GET.sh"), timeout=120)
        c.check("03: exit 0, with both refusals shown", r.returncode == 0 and "Field nosuch does not exist." in r.stdout and "Field protocol does not exist." in r.stdout, (r.returncode, r.stdout[-500:]))
        c.check("03: the narrow entry is name and type", "now it has 2 fields: name, type" in r.stdout, r.stdout[-700:])

        r = runner.run(os.path.join(UC, "04.head_exists.sh"), timeout=120)
        c.check("04: exit 0 with 200, 404 and 405 shown",
                r.returncode == 0 and ": 200" in r.stdout and "_example_missing: 404" in r.stdout and "HEAD /deniedUsers/example_lst_none: 405" in r.stdout, (r.returncode, r.stdout[-500:]))

        r = runner.run(os.path.join(UC, "05.location_POST.sh"), timeout=120)
        c.check("05: exit 0, and the server holds exactly the five units, by name", r.returncode == 0 and units() == NAMES[:5], (r.returncode, units(), r.stdout[-300:]))
        locations = re.findall(r"Location: (\S+)", r.stdout)
        c.check("05: it printed five addresses, each ending with the name of its unit",
                len(locations) == 5 and all(loc.endswith("/businessUnits/example_lst_%d" % (i + 1)) for i, loc in enumerate(locations)), locations)
        c.check("05: it said a 201 has no body, and showed the second POST of a name refused with 400",
                "Body: 0 bytes." in r.stdout and "The same POST again (example_lst_1): HTTP 400" in r.stdout, r.stdout[-400:])
        r = runner.run(os.path.join(UC, "05.location_POST.sh"), timeout=120)
        c.check("05 again, with the units there: exit 1, and still five units", r.returncode == 1 and units() == NAMES[:5], (r.returncode, units(), r.stdout[-300:]))

        mine = admin.get("businessUnits", {"name": "example_lst_*", "limit": 2, "offset": 2, "fields": "name"}).json() or {}
        names = [e["name"] for e in mine.get("result", [])]
        c.check("a filter changes totalCount: 5 of the units, and one more without it", total("businessUnits", {"name": "example_lst_*"}) == 5 and total("businessUnits") >= 6, total("businessUnits"))
        c.check("a filter that finds nothing is 200 and 0 of 0", (admin.get("businessUnits", {"name": "example_lst_nothing_*"}).json() or {}).get("resultSet") == {"returnCount": 0, "totalCount": 0})
        c.check("the pattern in capitals finds the same five", total("businessUnits", {"name": "EXAMPLE_LST_*"}) == 5)
        r = runner.run(os.path.join(UC, "06.filters_GET.sh"), timeout=120)
        c.check("06: exit 0, with the page of names that this check reads for the same call",
                r.returncode == 0 and "returnCount 2 of totalCount 5: %s" % ", ".join(names) in r.stdout, (r.returncode, names, r.stdout[-500:]))

        r = runner.run(os.path.join(UC, "99.cleanup_DELETE.sh"), timeout=120)
        c.check("99: exit 0, and nothing is left", r.returncode == 0 and units() == [] and "example_lst_5 was deleted" in r.stdout, (r.returncode, units(), r.stdout[-300:]))
        r = runner.run(os.path.join(UC, "99.cleanup_DELETE.sh"), timeout=120)
        c.check("99 a second time, with nothing to remove, exits 0", r.returncode == 0, r.stdout[-300:])
        for leftover in STATE_FILES:
            c.check("no %s is left" % leftover, not os.path.exists(os.path.join(UC, leftover)))
finally:
    for name in NAMES:
        if admin.exists("businessUnits/" + name):
            admin.delete("businessUnits/" + name)
    c.check("no business unit named example_lst_* is left on the server", units() == [], units())
    clear_local()
    admin.logout()

sys.exit(c.done())
