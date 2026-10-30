#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs EndUser/UseCases/08-lists-and-paging for real, with two throwaway end user accounts this check
creates and removes: one that may use the transfers web service and one that may not.

It proves what the use case and its README say, through the API on its own and not through the scripts:
  - the folder list answers an object with files and self (and parent below the home), no count; with no limit it holds
    every entry; limit and offset page it; limit=0 returns nothing; limit=-1 is not refused; limit=abc is 404; an unknown
    sortBy is ignored; fields= is ignored;
  - /transfers answers a plain array, 100 when no limit is given, the same for limit=0, more than 100 for limit=500,
    400 for limit=-1 and 404 for limit=abc; fields= is ignored; the account that may not use it is refused with 403;
  - the address book takes a limit and an offset, the secret questions take none;
  - an upload answers 201 with no body and a Location that ends with the encoded path, and a new folder has no Location.
Then it runs the scripts and compares what they printed with what it read: 00.run_all.sh exits 0 and cleans up (and for the
account that may not use transfers skips 03 and goes on), 01 leaves exactly the files it says, 02 reads every file, 03 says
the default page is 100, 06 counts the same number of transfers as a read with limit=500, 99 leaves nothing and can be run twice.

Needs --write and st_allow_writes="yes". The end user port is the one the other EndUser checks use. It does not run on the
bundled mock, which has no second port.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the lists and paging use case for real")

c = st_client.Checker("EndUser use case 08-lists-and-paging, run for real")

ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
UC = runner.path("EndUser", "UseCases", "08-lists-and-paging")
STATE_FILES = ("session.cookie.jar", "state.local.csrf")
FOLDER = "example_uc_lists"
ENDUSER_PORT = harness.ports(config).enduser

admin = harness.connect(config, c, mock="the bundled mock does not implement the EndUser API on a second port; run this against a real server to exercise it")


def clear_local():
    for leftover in STATE_FILES:
        p = os.path.join(UC, leftover)
        if os.path.exists(p):
            os.remove(p)


def run(account, script, args=None, timeout=300):
    cfg = dict(config, st_port=ENDUSER_PORT, st_user=account.name, st_password=account.password)
    with runner.real_credentials(ENDUSER_TREE, cfg):
        return runner.run(os.path.join(UC, script), args or [], timeout=timeout)


def client(account):
    user = st_client.EndUserClient(config["st_server"], ENDUSER_PORT, account.name, account.password)
    user.login()
    return user


def folder_names(user):
    got = user._request("GET", "files/" + FOLDER)
    return sorted(f["fileName"] for f in (got.json() or {}).get("files", [])) if got.status == 200 else None


def count_of(user, path, params=""):
    got = user._request("GET", path + ("?" + params if params else ""))
    body = got.json()
    if got.status != 200:
        return got.status, None
    return got.status, len(body["files"]) if isinstance(body, dict) and "files" in body else len(body)


try:
    name = "example_lst_%s" % harness.suffix(5)
    with harness.throwaway_account(admin, c, config, name=name + "_a", extra={"transfersWebServiceAllowed": True},
                                   label="set up: an account that may use the transfers web service") as allowed, \
         harness.throwaway_account(admin, c, config, name=name + "_n", label="set up: an account that may not") as denied:
        run(allowed, "99.cleanup_DELETE.sh")   # a folder an earlier crashed run left behind comes with the account name
        clear_local()

        # -- the whole use case, as each account ---------------------------------------------------------------
        r = run(allowed, "00.run_all.sh", ["3", "2"])
        c.check("00.run_all.sh as the account that may use transfers exits 0", r.returncode == 0, (r.stdout + r.stderr)[-500:])
        c.check("it ended with the cleanup, and 03 was not skipped", "Cleaned up." in r.stdout and "was skipped" not in r.stdout, r.stdout[-300:])
        owner = client(allowed)
        c.check("nothing is left of the folder", folder_names(owner) is None, folder_names(owner))
        clear_local()
        r = run(denied, "00.run_all.sh", ["3", "2"])
        c.check("00.run_all.sh as the account that may not use transfers exits 0", r.returncode == 0, (r.stdout + r.stderr)[-500:])
        c.check("it skipped 03 with its reason and went on to 06",
                "03.transfers_GET_list was skipped" in r.stdout and "403: the account may not use the transfers web service" in r.stdout
                and "Files in example_uc_lists: 3" in r.stdout and "Transfers are not counted:" in r.stdout, r.stdout[-700:])
        clear_local()
        refused = client(denied)._request("GET", "transfers")
        c.check("the API refuses that account /transfers with 403 and says why", refused.status == 403 and "not authorized to get/submit transfers" in refused.text, (refused.status, refused.text[:200]))
        for script, expected in (("03.transfers_GET_list.sh", 3), ("02.files_GET_list.sh", 1)):
            r = run(denied, script)
            c.check("%s for it before there is anything: exit %s" % (script, expected), r.returncode == expected, (r.returncode, r.stdout[-300:]))
        c.check("02 with no folder says to run 01", "Run 01.files_POST_location.sh first." in r.stdout, r.stdout[-300:])
        run(denied, "99.cleanup_DELETE.sh")
        clear_local()

        # -- step by step, as the account that may use transfers ------------------------------------------------
        r = run(allowed, "01.files_POST_location.sh", ["7"])
        c.check("01 exits 0", r.returncode == 0, (r.stdout + r.stderr)[-400:])
        wanted = ["lst_%02d.txt" % n for n in range(1, 8)]
        c.check("the folder holds exactly lst_01.txt to lst_07.txt", folder_names(owner) == wanted, folder_names(owner))
        locations = re.findall(r"Location: (https\S+)", r.stdout)
        c.check("01 printed a Location for each file, ending with the encoded path",
                len(locations) == 7 and all(loc.endswith("/files/%%2F%s%%2F%s" % (FOLDER, wanted[i])) for i, loc in enumerate(locations)), locations)
        c.check("and said that a new folder has no Location", "Location: none. A new folder has no Location header." in r.stdout, r.stdout[:300])
        r = run(allowed, "01.files_POST_location.sh", ["7"])
        c.check("01 again: the folder is used as it is, the files are replaced (201), and there are still seven",
                r.returncode == 0 and "is there already" in r.stdout and r.stdout.count("HTTP 201") == 7 and folder_names(owner) == wanted, (r.returncode, r.stdout[-300:], folder_names(owner)))
        r = run(allowed, "01.files_POST_location.sh", ["21"])
        c.check("01 with a COUNT of 21 is refused before any call (exit 2)", r.returncode == 2 and "from 1 to 20" in r.stdout, (r.returncode, r.stdout[-200:]))

        # what the README table says about the folder list, read here
        path = "files/" + FOLDER
        whole = owner._request("GET", path)
        body = whole.json() or {}
        c.check("the folder list is an object with files, parent and self, and no count", whole.status == 200 and sorted(body) == ["files", "parent", "self"], (whole.status, sorted(body)))
        c.check("with no limit every entry comes back (7)", len(body.get("files", [])) == 7)
        c.check("limit=3&offset=6 gives the last one", count_of(owner, path, "limit=3&offset=6") == (200, 1))
        c.check("limit=3&offset=20 is a 200 with nothing", count_of(owner, path, "limit=3&offset=20") == (200, 0))
        c.check("limit=0 returns no entry at all", count_of(owner, path, "limit=0") == (200, 0))
        c.check("limit=-1 is not refused: every entry", count_of(owner, path, "limit=-1") == (200, 7))
        bad = owner._request("GET", path + "?limit=abc")
        c.check("limit=abc is 404 'HTTP 404 Not Found'", bad.status == 404 and "HTTP 404 Not Found" in bad.text, (bad.status, bad.text[:100]))
        ordered = owner._request("GET", path + "?sortBy=fileName&order=DESC").json() or {}
        c.check("sortBy=fileName&order=DESC starts at lst_07.txt", [f["fileName"] for f in ordered.get("files", [])] == wanted[::-1])
        by_size = owner._request("GET", path + "?sortBy=size&order=ASC")
        c.check("sortBy=size is accepted", by_size.status == 200 and len((by_size.json() or {}).get("files", [])) == 7, by_size.status)
        c.check("an unknown sortBy is ignored (200)", owner._request("GET", path + "?sortBy=nosuch").status == 200)
        narrow = (owner._request("GET", path + "?fields=fileName").json() or {}).get("files", [{}])[0]
        c.check("fields=fileName on the folder list changes nothing: the entry has the same fields",
                sorted(narrow) == sorted(body["files"][0]), (sorted(narrow), sorted(body["files"][0])))
        me = owner._request("GET", "myself").json() or {}
        me_narrow = owner._request("GET", "myself?fields=name").json() or {}
        c.check("fields=name on /myself changes nothing", sorted(me_narrow) == sorted(me) and len(me) > 3, (sorted(me_narrow), sorted(me)))

        r = run(allowed, "02.files_GET_list.sh", ["3"])
        c.check("02: exit 0, seven entries in three pages, the last shorter than 3", r.returncode == 0 and "holds all 7 entries" in r.stdout and "Read 7 entries in 3 pages, the last one shorter than 3" in r.stdout, (r.returncode, r.stdout[-600:]))
        c.check("02: limit=0 is none, the sort ends are right, abc is 404 and -1 is every entry",
                "limit=0: HTTP 200, 0 entries" in r.stdout and "first lst_07.txt, last lst_01.txt" in r.stdout
                and "limit=abc: HTTP 404, HTTP 404 Not Found" in r.stdout and "limit=-1: HTTP 200, 7 entries" in r.stdout, r.stdout[-600:])

        # /transfers needs more than a hundred entries to show that a hundred is the default page and not a cap
        extra = 0
        for n in range(8, 100):
            up = owner.upload_to(FOLDER, "lst_%02d.txt" % n, b"x\n")
            if up.status != 201:
                c.check("an upload of lst_%02d.txt for the long transfer list" % n, False, (up.status, up.text[:100]))
                break
            extra += 1
        everything = owner._request("GET", "transfers?limit=1000").json() or []
        c.check("the account has more than a page of transfers (%s)" % len(everything), len(everything) > 100, len(everything))
        default = owner._request("GET", "transfers")
        c.check("/transfers is a plain array, and with no limit it holds 100", default.status == 200 and isinstance(default.json(), list) and len(default.json()) == 100, (default.status, len(default.json() or [])))
        c.check("limit=0 gives the same 100", count_of(owner, "transfers", "limit=0") == (200, 100))
        c.check("limit=500 gives every one of them: 100 is not a cap", count_of(owner, "transfers", "limit=500") == (200, len(everything)))
        c.check("limit=10&offset=100 gives what is past the first hundred", count_of(owner, "transfers", "limit=10&offset=100") == (200, min(10, len(everything) - 100)))
        negative = owner._request("GET", "transfers?limit=-1")
        c.check("limit=-1 is 400 'Parameter should be a positive number or 0.'", negative.status == 400 and "Parameter should be a positive number or 0." in negative.text, (negative.status, negative.text[:100]))
        letters = owner._request("GET", "transfers?limit=abc")
        c.check("limit=abc is 404", letters.status == 404, letters.status)
        t_narrow = (owner._request("GET", "transfers?fields=filename").json() or [{}])[0]
        c.check("fields=filename on /transfers changes nothing", sorted(t_narrow) == sorted(default.json()[0]), (sorted(t_narrow), sorted(default.json()[0])))
        c.check("the list names the file filename and the direction direction", "filename" in default.json()[0] and "direction" in default.json()[0])

        r = run(allowed, "03.transfers_GET_list.sh", ["5"])
        c.check("03: exit 0, a hundred entries said to be the default page, limit=0 the same, -1 is 400 and abc is 404",
                r.returncode == 0 and "plain array of 100 entries" in r.stdout and "That is the default page of 100." in r.stdout and "limit=0: HTTP 200, 100 entries" in r.stdout
                and "limit=-1: HTTP 400" in r.stdout and "limit=abc: HTTP 404" in r.stdout, (r.returncode, r.stdout[-700:]))
        r = run(allowed, "06.counting_without_totalCount.sh")
        c.check("06: exit 0, the files and the transfers counted the way this check read them",
                r.returncode == 0 and "Files in %s: 99, counted in 1 calls of up to 100." % FOLDER in r.stdout
                and "Transfers: %s, counted in 2 calls of up to 100." % len(everything) in r.stdout
                and "would have missed %s." % (len(everything) - 100) in r.stdout, (r.returncode, len(everything), r.stdout[-500:]))
        r = run(allowed, "06.counting_without_totalCount.sh", ["10"])
        c.check("06 with a page of 10: the same count, in %s calls" % (-(-len(everything) // 10)),
                r.returncode == 0 and "Transfers: %s, counted in %s calls of up to 10." % (len(everything), -(-len(everything) // 10)) in r.stdout, r.stdout[-400:])
        r = run(allowed, "02.files_GET_list.sh", ["10"])
        c.check("02 on 99 files, ten a page: ten pages, the last of 9", r.returncode == 0 and "Read 99 entries in 10 pages" in r.stdout, r.stdout[-500:])

        book = owner._request("GET", "myself/addressBook")
        c.check("the address book is a plain array", book.status == 200 and isinstance(book.json(), list))
        c.check("and takes a limit and an offset", count_of(owner, "myself/addressBook", "limit=1") == (200, 1) and count_of(owner, "myself/addressBook", "limit=1&offset=1") == (200, 1))
        questions = owner._request("GET", "secretQuestions").json() or []
        c.check("/secretQuestions is a plain array of text that takes no limit", len(questions) > 2 and all(isinstance(q, str) for q in questions)
                and count_of(owner, "secretQuestions", "limit=2") == (200, len(questions)), len(questions))
        r = run(allowed, "04.addressBook_GET.sh")
        c.check("04: exit 0, and the questions are said to take no limit", r.returncode == 0 and "This list takes no limit." in r.stdout, (r.returncode, r.stdout[-400:]))
        r = run(allowed, "05.fields_not_offered.sh")
        c.check("05: exit 0, with fields= making no difference three times", r.returncode == 0 and r.stdout.count("fields= made no difference.") == 3, (r.returncode, r.stdout[-500:]))

        # -- nothing left -----------------------------------------------------------------------------------------
        r = run(allowed, "99.cleanup_DELETE.sh")
        c.check("99: exit 0, 99 files and the folder deleted", r.returncode == 0 and "Deleted 99 files from %s." % FOLDER in r.stdout and "was deleted." in r.stdout, (r.returncode, r.stdout[-300:]))
        c.check("and the folder is gone", folder_names(owner) is None)
        r = run(allowed, "99.cleanup_DELETE.sh")
        c.check("99 a second time, with nothing to remove, exits 0", r.returncode == 0 and "nothing to delete" in r.stdout, (r.returncode, r.stdout[-200:]))
        for leftover in STATE_FILES:
            c.check("no %s is left" % leftover, not os.path.exists(os.path.join(UC, leftover)))
        owner.logout()
finally:
    clear_local()
    admin.logout()

sys.exit(c.done())
