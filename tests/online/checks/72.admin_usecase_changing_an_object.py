#!/usr/bin/env python3
"""
WRITES TO THE SERVER (a throwaway account and route, and ONE option that it puts back). Runs Admin/UseCases/05-changing-an-object for real.

The objects are example_chg_<random> (an account) and example_chg_<random>_route. The one setting of the server that is touched is the option
AddressBook.Limit.MaxDisplayEntries, for a moment: the check reads it before and after through its own session and asserts the answer is the same,
field for field.

What it proves, through its own session on the Admin API and not through what the scripts print:
  - 00.run_all.sh runs the whole way (01 to 11, then 99), no step says "NOT AS DOCUMENTED", and nothing is left: no account, no route, no state file.
  - The type of the value decides how a PATCH is written, tried again by this check with its own calls on the objects the scripts made:
      string  : replace, add and remove; a number sent to a text field is stored as text; a list is refused; the empty text is stored as null;
      number  : a number with no quotes is stored as a number (a JSON number, not text); "7" in quotes is converted; 2.5 is cut to 2; "abc" and -1 are refused;
                remove puts the default back (3); uid is text, so 60000 is stored as "60000";
      boolean : true and false are stored as booleans; "false" and 1 are converted; "yes" is refused; remove puts false back;
      list    : add at the end (-), add at a position, replace one item, remove one by position, a position past the end and an id in the path are
                refused, remove with - removes nothing, replace of the whole list is the whole list;
      object  : replace takes the whole object (what it leaves out is reset to null), remove leaves its fields null, null for it is refused.
  - A patch is all or nothing; a typo in the path of an add is answered 204 and stores nothing.
  - A PUT of the object as read changes one field and nothing else; a PUT of a fragment removes the steps of a route, and a PATCH puts them back.
  - The option is back exactly as it was, and the number of accounts is what it was at the start.

Needs --write and st_allow_writes="yes". Takes about a minute. On the bundled mock it ends at once: the mock has no routes with steps.
"""
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the Admin use case 05 for real")

c = st_client.Checker("Admin use case 05, changing an object, run for real")

ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
UC = runner.path("Admin", "UseCases", "05-changing-an-object")
STATE_FILES = ("session.cookie.jar", "state.local.csrf", "state.local.route_id", "state.local.option.json", "state.local.account.json", "state.local.route.json")
OPTION = "AddressBook.Limit.MaxDisplayEntries"

admin = harness.connect(config, c, mock="the bundled mock has no routes with steps and no PATCH of them; run this against a real server to exercise it")


def clear_local():
    for leftover in STATE_FILES:
        p = os.path.join(UC, leftover)
        if os.path.exists(p):
            os.remove(p)


def option_now():
    result = admin.get("configurations/options", params={"name": OPTION}).json().get("result", [])
    return result[0] if result else None


def accounts_total():
    return admin.get("accounts", params={"limit": 1, "fields": "name"}).json().get("resultSet", {}).get("totalCount")


def route_id(name):
    found = [r for r in admin.results("routes", {"name": name, "fields": "id,name"}) if r.get("name") == name]
    return found[0]["id"] if len(found) == 1 else None


name = "example_chg_" + harness.suffix(6)
route_name = name + "_route"
account_path = "accounts/" + name

option_before = option_now()
total_before = accounts_total()
c.check("the option %s is there to be changed for a moment, and is not read only" % OPTION, option_before is not None and option_before.get("readOnly") is False, option_before)

try:
    with runner.real_credentials(ADMIN_TREE, config):
        # ---- the whole use case --------------------------------------------------------------------------------------------
        r = runner.run(os.path.join(UC, "00.run_all.sh"), [name], timeout=600)
        out = r.stdout + r.stderr
        c.check("00.run_all.sh exits 0", r.returncode == 0, out.strip()[-500:])
        c.check("no case says NOT AS DOCUMENTED", "NOT AS DOCUMENTED" not in out, [l for l in out.splitlines() if "NOT AS DOCUMENTED" in l][:3])
        c.check("it ended with the cleanup", "Cleaned up." in out, out[-200:])
        c.check("no account is left", admin.get(account_path).status == 404)
        c.check("no route is left", route_id(route_name) is None)
        c.check("the option is back exactly as it was", option_now() == option_before, (option_before, option_now()))
        for leftover in STATE_FILES:
            c.check("no %s is left" % leftover, not os.path.exists(os.path.join(UC, leftover)))
        r = runner.run(os.path.join(UC, "00.run_all.sh"), ["real_account"], timeout=60)
        c.check("00 with a name that is not example_* is refused at once (exit 2) and touches nothing", r.returncode == 2 and "Usage: ./00.run_all.sh" in r.stdout, r.stdout[-200:])

        # ---- the steps one by one, and what each type does, proved with this check's own calls --------------------------------
        def step(script, *args, expect=0):
            r = runner.run(os.path.join(UC, script), [name] + list(args), timeout=300)
            c.check("%s exits %s" % (script, expect), r.returncode == expect, (r.stdout + r.stderr).strip()[-400:])
            return r

        step("01.object_POST.sh")
        account = admin.get(account_path).json()
        rid = route_id(route_name)
        c.check("01 made the account, with a text email, a number that is a number and a uid that is text",
                account.get("contact", {}).get("email") == name + "@example.com" and isinstance(account["user"]["failedAuthMaximum"], int)
                and isinstance(account["uid"], str), account.get("uid"))
        c.check("01 made the route with its two steps in order", rid is not None
                and [s["fileFilterExpression"] for s in admin.get("routes/" + rid).json()["steps"]] == ["*.one", "*.two"])
        r = step("01.object_POST.sh", expect=1)
        c.check("01 a second time is refused and says the account exists", "already exists" in r.stdout, r.stdout[-200:])
        step("02.object_GET.sh")
        c.check("02 kept a copy of the account and of the route", os.path.getsize(os.path.join(UC, "state.local.account.json")) > 0
                and os.path.getsize(os.path.join(UC, "state.local.route.json")) > 0)
        uid_before = account["uid"]
        for script in ("03.patch_string.sh", "04.patch_number.sh", "05.patch_boolean.sh", "06.patch_list.sh", "07.patch_null_and_object.sh", "08.patch_mistakes.sh"):
            r = step(script)
            c.check("%s: no case came out other than documented" % script, "NOT AS DOCUMENTED" not in r.stdout, [l for l in r.stdout.splitlines() if "NOT AS DOCUMENTED" in l][:2])
        # the state the steps leave: 04 puts the uid and the policy back, 05 the booleans, 06 the list
        account = admin.get(account_path).json()
        c.check("04 left the uid as text, as it was", account["uid"] == uid_before, account["uid"])
        c.check("05 left the booleans false", account["authByEmail"] is False and account["transfersWebServiceAllowed"] is False and account["disabled"] is False)
        c.check("06 left the route with its two steps", [s["fileFilterExpression"] for s in admin.get("routes/" + rid).json()["steps"]] == ["*.one", "*.two"])

        def patch(path, ops):
            return admin.patch(path, ops)

        def stored(path, *keys):
            value = admin.get(path).json()
            for key in keys:
                value = value[key]
            return value

        # ---- string -----------------------------------------------------------------------------------------------------------
        c.check("string: replace of a text that is null: 204", patch(account_path, [{"op": "replace", "path": "/notes", "value": "own note"}]).status == 204)
        c.check("string: stored as text", stored(account_path, "notes") == "own note")
        c.check("string: a number sent to a text field is stored as text", patch(account_path, [{"op": "replace", "path": "/notes", "value": 5}]).status == 204
                and stored(account_path, "notes") == "5")
        r = patch(account_path, [{"op": "replace", "path": "/notes", "value": ["a"]}])
        c.check("string: a list is refused (400) and nothing changes", r.status == 400 and stored(account_path, "notes") == "5", r.status)
        c.check("string: the empty text is stored as null", patch(account_path, [{"op": "replace", "path": "/notes", "value": ""}]).status == 204
                and stored(account_path, "notes") is None)
        c.check("string: add sets a field that is null", patch(account_path, [{"op": "add", "path": "/contact/phone", "value": "+1"}]).status == 204
                and stored(account_path, "contact", "phone") == "+1")
        c.check("string: remove leaves the key, with null", patch(account_path, [{"op": "remove", "path": "/contact/phone"}]).status == 204
                and "phone" in stored(account_path, "contact") and stored(account_path, "contact", "phone") is None)

        # ---- number -----------------------------------------------------------------------------------------------------------
        def max_auth():
            return stored(account_path, "user", "failedAuthMaximum")

        c.check("number: 5 with no quotes is stored as the number 5", patch(account_path, [{"op": "replace", "path": "/user/failedAuthMaximum", "value": 5}]).status == 204
                and max_auth() == 5 and isinstance(max_auth(), int) and not isinstance(max_auth(), bool))
        c.check("number: \"7\" in quotes is converted: stored as the number 7, not as text", patch(account_path, [{"op": "replace", "path": "/user/failedAuthMaximum", "value": "7"}]).status == 204
                and max_auth() == 7 and isinstance(max_auth(), int))
        r = patch(account_path, [{"op": "replace", "path": "/user/failedAuthMaximum", "value": "abc"}])
        c.check("number: a text that is not a number is refused (400) and nothing changes", r.status == 400 and max_auth() == 7, (r.status, max_auth()))
        c.check("number: 2.5 is accepted for a whole number and stored as 2", patch(account_path, [{"op": "replace", "path": "/user/failedAuthMaximum", "value": 2.5}]).status == 204
                and max_auth() == 2)
        r = patch(account_path, [{"op": "replace", "path": "/user/failedAuthMaximum", "value": -1}])
        c.check("number: -1 is refused (400)", r.status == 400 and max_auth() == 2, (r.status, max_auth()))
        c.check("number: remove puts the default (3) back, not null", patch(account_path, [{"op": "remove", "path": "/user/failedAuthMaximum"}]).status == 204 and max_auth() == 3)
        c.check("number: uid is text, so a number sent to it is stored as text", patch(account_path, [{"op": "replace", "path": "/uid", "value": 60000}]).status == 204
                and stored(account_path, "uid") == "60000")
        patch(account_path, [{"op": "replace", "path": "/uid", "value": uid_before}])
        c.check("number: the old uid is back, as text", stored(account_path, "uid") == uid_before)

        # ---- boolean ----------------------------------------------------------------------------------------------------------
        def flag():
            return stored(account_path, "transfersWebServiceAllowed")

        c.check("boolean: true with no quotes is stored as true", patch(account_path, [{"op": "replace", "path": "/transfersWebServiceAllowed", "value": True}]).status == 204 and flag() is True)
        c.check("boolean: \"false\" in quotes is converted to false", patch(account_path, [{"op": "replace", "path": "/transfersWebServiceAllowed", "value": "false"}]).status == 204 and flag() is False)
        r = patch(account_path, [{"op": "replace", "path": "/transfersWebServiceAllowed", "value": "yes"}])
        c.check("boolean: \"yes\" is refused (400) and nothing changes", r.status == 400 and flag() is False, (r.status, flag()))
        c.check("boolean: 1 is converted to true", patch(account_path, [{"op": "replace", "path": "/transfersWebServiceAllowed", "value": 1}]).status == 204 and flag() is True)
        c.check("boolean: remove puts false back, not null", patch(account_path, [{"op": "remove", "path": "/transfersWebServiceAllowed"}]).status == 204 and flag() is False)
        r = patch(account_path, [{"op": "replace", "path": "/disabled", "value": None}])
        c.check("boolean: null on a field that must have a value is refused (400)", r.status == 400 and stored(account_path, "disabled") is False, r.status)

        # ---- list (the steps of the route) ----------------------------------------------------------------------------------------
        route_path = "routes/" + rid

        def step_json(filter_text):
            return {"type": "EncodingConversion", "status": "ENABLED", "conditionType": "ALWAYS", "usePrecedingStepFiles": False,
                    "fileFilterExpression": filter_text, "fileFilterExpressionType": "GLOB", "inputCharset": "UTF-8", "outputCharset": "UTF-8",
                    "actionOnStepFailure": "PROCEED"}

        def filters():
            return [s["fileFilterExpression"] for s in stored(route_path, "steps")]

        c.check("list: add at the end (the path ends in -)", patch(route_path, [{"op": "add", "path": "/steps/-", "value": step_json("*.three")}]).status == 204
                and filters() == ["*.one", "*.two", "*.three"], filters())
        c.check("list: add at position 0: the others move down", patch(route_path, [{"op": "add", "path": "/steps/0", "value": step_json("*.zero")}]).status == 204
                and filters() == ["*.zero", "*.one", "*.two", "*.three"], filters())
        c.check("list: replace one field of the item at position 1", patch(route_path, [{"op": "replace", "path": "/steps/1/fileFilterExpression", "value": "*.uno"}]).status == 204
                and filters() == ["*.zero", "*.uno", "*.two", "*.three"], filters())
        c.check("list: remove the item at position 0: the others move up", patch(route_path, [{"op": "remove", "path": "/steps/0"}]).status == 204
                and filters() == ["*.uno", "*.two", "*.three"], filters())
        r = patch(route_path, [{"op": "add", "path": "/steps/9", "value": step_json("*.nine")}])
        c.check("list: a position past the end is refused (400)", r.status == 400 and filters() == ["*.uno", "*.two", "*.three"], (r.status, filters()))
        first_id = stored(route_path, "steps")[0]["id"]
        r = patch(route_path, [{"op": "replace", "path": "/steps/%s/status" % first_id, "value": "DISABLED"}])
        c.check("list: the id of an item in the path is refused (400)", r.status == 400 and stored(route_path, "steps")[0]["status"] == "ENABLED", r.status)
        c.check("list: remove with - answers 204 and removes nothing", patch(route_path, [{"op": "remove", "path": "/steps/-"}]).status == 204
                and filters() == ["*.uno", "*.two", "*.three"], filters())
        c.check("list: the whole list replaced with an empty one: no step is left", patch(route_path, [{"op": "replace", "path": "/steps", "value": []}]).status == 204 and filters() == [])
        c.check("list: replaced with two steps: the list is what was sent",
                patch(route_path, [{"op": "replace", "path": "/steps", "value": [step_json("*.one"), step_json("*.two")]}]).status == 204 and filters() == ["*.one", "*.two"], filters())

        # ---- null and object --------------------------------------------------------------------------------------------------
        c.check("null: replace with null clears a field that may be empty", patch(account_path, [{"op": "replace", "path": "/contact/email", "value": None}]).status == 204
                and stored(account_path, "contact", "email") is None)
        full = {"policy": "custom", "inboundLimit": 100, "outboundLimit": 200}
        c.check("object: replace of the whole object", patch(account_path, [{"op": "replace", "path": "/bandwidthLimits", "value": full}]).status == 204
                and stored(account_path, "bandwidthLimits") == full)
        c.check("object: replace with a fragment resets what it leaves out (outboundLimit becomes null)",
                patch(account_path, [{"op": "replace", "path": "/bandwidthLimits", "value": {"policy": "custom", "inboundLimit": 100}}]).status == 204
                and stored(account_path, "bandwidthLimits") == {"policy": "custom", "inboundLimit": 100, "outboundLimit": None}, stored(account_path, "bandwidthLimits"))
        patch(account_path, [{"op": "replace", "path": "/bandwidthLimits", "value": {"policy": "default"}}])
        c.check("object: remove leaves the object with every field null", patch(account_path, [{"op": "remove", "path": "/contact"}]).status == 204
                and stored(account_path, "contact") == {"email": None, "phone": None}, stored(account_path, "contact"))
        r = patch(account_path, [{"op": "replace", "path": "/contact", "value": None}])
        c.check("object: null for an object is refused (400)", r.status == 400, r.status)

        # ---- mistakes ---------------------------------------------------------------------------------------------------------
        r = patch(account_path, [{"op": "replace", "path": "/notes", "value": "first"}, {"op": "replace", "path": "/nosuchfield", "value": "second"}])
        c.check("mistake: a patch is all or nothing (400, and the first operation is not applied)", r.status == 400 and stored(account_path, "notes") is None, (r.status, stored(account_path, "notes")))
        keys_before = sorted(stored(account_path, "contact"))
        r = patch(account_path, [{"op": "add", "path": "/contact/phon", "value": "x"}])
        c.check("mistake: a typo in the path of an add is 204 and stores nothing", r.status == 204 and sorted(stored(account_path, "contact")) == keys_before == ["email", "phone"], r.status)
        r = patch(account_path, [{"op": "replace", "path": "/nosuchfield", "value": "x"}])
        c.check("mistake: replace of a field the object does not have is 400 Missing field", r.status == 400 and "Missing field" in json.dumps(r.json()), r.text[:200])
        # the client of this check always sends JSON, so the request with another Content-Type is made by hand, on its session
        raw = urllib.request.Request(admin.base + account_path, data=json.dumps([{"op": "replace", "path": "/notes", "value": "x"}]).encode(),
                                     headers={"Referer": admin.referer, "Accept": "application/json", "csrfToken": admin._csrf or "", "Content-Type": "text/plain"}, method="PATCH")
        try:
            raw_status = admin._opener.open(raw, timeout=30).status
        except urllib.error.HTTPError as e:
            raw_status = e.code
        c.check("mistake: Content-Type text/plain is 415 and nothing changes", raw_status == 415 and stored(account_path, "notes") is None, raw_status)

        # ---- PUT --------------------------------------------------------------------------------------------------------------
        step("09.put_whole_object.sh")
        c.check("09 changed the description and left the two steps", stored(route_path, "description") == "no metadata" and filters() == ["*.one", "*.two"], (stored(route_path, "description"), filters()))
        saved_route = admin.get(route_path).json()
        fragment = {k: saved_route[k] for k in ("name", "type", "conditionType")}
        fragment["description"] = "own fragment"
        c.check("PUT of a fragment: 204", admin.put(route_path, fragment).status == 204)
        c.check("PUT of a fragment: the steps are gone, and the server said nothing", filters() == [], filters())
        r = admin.put(route_path, {k: v for k, v in saved_route.items() if k != "metadata"})
        c.check("PUT of the old copy is refused (404: its step ids no longer exist) and the steps stay gone", r.status == 404 and filters() == [], (r.status, filters()))
        steps_back = [{k: v for k, v in s.items() if k not in ("id", "precedingStep", "metadata")} for s in saved_route["steps"]]
        c.check("PATCH of the list puts the steps back", patch(route_path, [{"op": "replace", "path": "/steps", "value": steps_back}]).status == 204
                and filters() == ["*.one", "*.two"], filters())
        patch(route_path, [{"op": "replace", "path": "/description", "value": "no metadata"}])
        step("10.put_fragment.sh")
        c.check("10 left the two steps and the description it found", filters() == ["*.one", "*.two"] and stored(route_path, "description") == "no metadata",
                (filters(), stored(route_path, "description")))

        # ---- the option ---------------------------------------------------------------------------------------------------------
        r = runner.run(os.path.join(UC, "11.options_save_change_restore.sh"), [], timeout=120)
        c.check("11 exits 0", r.returncode == 0, (r.stdout + r.stderr)[-400:])
        c.check("11 says the option is as it was", "is as it was" in r.stdout, r.stdout[-300:])
        c.check("11 changed it to 77 for a moment (the script said so) and left the option exactly as it was", option_now() == option_before, (option_before, option_now()))
        r = runner.run(os.path.join(UC, "11.options_save_change_restore.sh"), [OPTION, "100"], timeout=60)
        c.check("11 with the value the option has is refused (exit 1) and changes nothing", r.returncode == 1 and "already has the value" in r.stdout and option_now() == option_before, r.stdout[-200:])
        # a run stopped half way is put back by 99: save, change by hand, run 99
        with open(os.path.join(UC, "state.local.option.json"), "w") as f:
            json.dump(option_before, f)
        c.check("(the check changes the option by hand, as a stopped run would leave it)",
                admin.put("configurations/options", [{"name": OPTION, "values": ["77"]}]).status == 204 and option_now()["values"] == ["77"])
        r = step("99.cleanup_DELETE.sh")
        c.check("99 puts a changed option back from the saved copy, and deletes the objects",
                "was put back as saved" in r.stdout and option_now() == option_before and admin.get(account_path).status == 404 and route_id(route_name) is None, r.stdout[-400:])
        r = step("99.cleanup_DELETE.sh")
        c.check("99 a second time, with nothing to remove, says so", "nothing to delete" in r.stdout, r.stdout[-200:])
        for leftover in STATE_FILES:
            c.check("no %s is left after 99" % leftover, not os.path.exists(os.path.join(UC, leftover)))
finally:
    clear_local()
    for leftover_route in [route_id(route_name)]:
        if leftover_route:
            admin.delete("routes/" + leftover_route)
            c.info("the route %s was removed by hand" % route_name)
    if admin.exists(account_path):
        admin.delete(account_path)
        c.info("the account %s was removed by hand" % name)
    if option_before is not None and option_now() != option_before:
        admin.put("configurations/options", [{"name": OPTION, "values": option_before["values"]}])
        c.info("the option %s was put back by hand" % OPTION)
    c.check("the option is exactly as it was at the start", option_now() == option_before, (option_before, option_now()))
    c.check("the number of accounts is what it was at the start", accounts_total() == total_before, (total_before, accounts_total()))
    admin.logout()

sys.exit(c.done())
