#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 09.CompositeRoutes examples 08
(HEAD), 09 (PUT) and 10 (PATCH) against throwaway routes: a simple route with
two steps (Compress, Rename), a route template, and a composite route on a
throwaway account and subscription that runs the simple route. Each effect is
read back through the API.

It shows what the examples teach and the reference does not say:
  - HEAD answers 200 for a route of every type, and the script refuses a name
    that matches no route, or two routes (two simple routes may share a name);
  - a PUT that is sent back whole keeps the steps (and their ids), the
    subscription and the template, and changes only what was asked; the raw PUT
    of a fragment, made once, answers 204 and silently removes every step;
  - a PATCH addresses a step by its position, never by its id (400), reaches a
    composite route's step, inserts into the middle of the steps (the steps'
    precedingStep links follow), refuses type and id, and refuses a new
    routeTemplate;
  - a route that another route runs cannot be deleted ("Route is in use"), and
    deleting the route that runs it deletes it too.

Nothing is run: the routes are only created, read, changed and deleted, so no
stand-in server is needed. Refuses to start when any example_routes_* object
exists, and removes everything it made in a finally block. Needs --write and
st_allow_writes="yes".
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the route examples for real")

c = st_client.Checker("Routes, run for real from Admin/API 2.0/bash/09.CompositeRoutes (08 to 10)")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "09.CompositeRoutes")
ACCOUNT, APPLICATION = "example_routes_user", "example_routes_app"
SIMPLE, TEMPLATE, COMPOSITE = "example_routes_simple", "example_routes_template", "example_routes_composite"
PASSWORD = harness.new_password()


script = harness.bind_script(c, FOLDER, timeout=90)


def location_id(response):
    return response.headers.get("Location", "").rsplit("/", 1)[-1]


def by_name(name):
    return (admin.get("routes", params={"name": name, "fields": "id,name"}).json() or {}).get("result", [])


def route(route_id):
    return admin.get("routes/" + route_id).json()


def shape(r):
    """What a PUT must not lose: the steps (ids, types, status) and the links."""
    return ([(s["id"], s["type"], s["status"]) for s in r.get("steps") or []], r.get("subscriptions"),
            r.get("routeTemplate"), r.get("account"), r.get("name"), r.get("conditionType"))


def step(output):
    return {"type": "Rename", "status": "ENABLED", "conditionType": "ALWAYS", "usePrecedingStepFiles": False,
            "fileFilterExpressionType": "GLOB", "fileFilterExpression": "*", "outputFileName": output, "actionOnStepFailure": "FAIL"}


admin = harness.connect(config, c, mock="the bundled mock does not implement the route operations these examples use")
if (admin.exists("accounts/" + ACCOUNT) or admin.exists("applications/" + APPLICATION)
        or any(by_name(n) for n in (SIMPLE, TEMPLATE, COMPOSITE))):
    c.check("none of the example_routes_* objects exist yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

routes_before = (admin.get("routes", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount")
ids = {}
try:
    made = admin.post("accounts", {"name": ACCOUNT, "type": "user", "uid": "1072", "gid": "1072", "homeFolder": "/home/" + ACCOUNT,
                                   "user": {"name": ACCOUNT, "passwordCredentials": {"password": PASSWORD}}})
    c.check("set up: the account", made.status == 201, made.text[:200])
    c.check("set up: the Advanced Routing application",
            admin.post("applications", {"type": "AdvancedRouting", "name": APPLICATION, "notes": "routes check"}).status == 201)
    r = admin.post("subscriptions", {"type": "AdvancedRouting", "account": ACCOUNT, "application": APPLICATION, "folder": "/example_routes"})
    ids["subscription"] = location_id(r)
    c.check("set up: the subscription", r.status == 201, r.text[:200])
    r = admin.post("routes", {"type": "TEMPLATE", "name": TEMPLATE, "conditionType": "MATCH_ALL"})
    ids["template"] = location_id(r)
    c.check("set up: the route template", r.status == 201, r.text[:200])
    r = admin.post("routes", {"type": "TEMPLATE", "name": TEMPLATE + "2", "conditionType": "MATCH_ALL"})
    ids["template2"] = location_id(r)
    c.check("set up: a second route template", r.status == 201, r.text[:200])
    r = admin.post("routes", {"type": "SIMPLE", "name": SIMPLE, "conditionType": "ALWAYS", "condition": True, "steps": [
        {"type": "Compress", "status": "ENABLED", "conditionType": "ALWAYS", "usePrecedingStepFiles": False,
         "fileFilterExpressionType": "GLOB", "fileFilterExpression": "*", "singleArchiveEnabled": True,
         "singleArchiveName": "a.zip", "compressionType": "ZIP", "compressionLevel": "STORE", "actionOnStepFailure": "FAIL"},
        step("renamed.zip")]})
    ids["simple"] = location_id(r)
    c.check("set up: the simple route", r.status == 201, r.text[:200])
    r = admin.post("routes", {"type": "COMPOSITE", "account": ACCOUNT, "name": COMPOSITE, "conditionType": "MATCH_ALL",
                              "routeTemplate": ids["template"], "subscriptions": [ids["subscription"]],
                              "steps": [{"type": "ExecuteRoute", "status": "ENABLED", "autostart": False, "executeRoute": ids["simple"]}]})
    ids["composite"] = location_id(r)
    c.check("set up: the composite route that runs the simple route", r.status == 201, r.text[:200])

    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        # 08 HEAD
        for name, kind in ((SIMPLE, "simple"), (TEMPLATE, "template"), (COMPOSITE, "composite")):
            out = script("08.routes_id_HEAD.sh", [name])
            c.check("08 a %s route exists, and the id printed is its own" % kind,
                    "The route %s exists, id %s." % (name, ids[kind]) in out, out[-200:])
        out = script("08.routes_id_HEAD.sh", ["example_routes_nope"], expect_rc=1)
        c.check("08 a name that matches nothing is refused, with the count", "Found 0 routes" in out, out[-200:])
        out = script("08.routes_id_HEAD.sh", ["example_routes_simp*"], expect_rc=1)
        c.check("08 a wildcard is not a name: the exact name is what counts", "Found 0 routes" in out, out[-200:])
        r = admin.post("routes", {"type": "SIMPLE", "name": SIMPLE, "conditionType": "ALWAYS", "steps": [step("dup")]})
        ids["duplicate"] = location_id(r)
        c.check("two simple routes may have the same name", r.status == 201, r.text[:200])
        out = script("08.routes_id_HEAD.sh", [SIMPLE], expect_rc=1)
        c.check("08 two routes of that name are refused, with the count", "Found 2 routes" in out, out[-200:])
        for name, args in (("09.routes_id_PUT.sh", [SIMPLE, "x"]), ("10.routes_id_PATCH.sh", [SIMPLE, "Rename"])):
            script(name, args, expect_rc=1)
        c.check("09 and 10 changed neither of the two routes",
                route(ids["duplicate"]).get("description") is None and route(ids["simple"]).get("description") is None
                and route(ids["duplicate"])["steps"][0]["status"] == "ENABLED" and route(ids["simple"])["steps"][1]["status"] == "ENABLED")

        # What 09 guards against: a PUT of a fragment. Made once, on the duplicate, which is then deleted.
        fragment = admin.put("routes/" + ids["duplicate"], {"type": "SIMPLE", "name": SIMPLE, "conditionType": "ALWAYS", "description": "fragment"})
        c.check("the raw PUT of a fragment answers 204 ...", fragment.status == 204, fragment.text[:200])
        after = route(ids["duplicate"])
        c.check("... and silently removed every step, keeping the description", after["steps"] == [] and after["description"] == "fragment",
                (len(after["steps"]), after["description"]))
        c.check("the duplicate can be deleted", admin.delete("routes/" + ids.pop("duplicate")).status == 204)

        # 09 PUT
        before = route(ids["simple"])
        out = script("09.routes_id_PUT.sh", [SIMPLE, "A new description"])
        after = route(ids["simple"])
        c.check("09 the description is replaced", after["description"] == "A new description", after["description"])
        c.check("09 the steps, with their ids, and everything else are as they were", shape(after) == shape(before) and
                [s.get("compressionType") for s in after["steps"]] == ["ZIP", None] and after["steps"][1]["outputFileName"] == "renamed.zip",
                (shape(before), shape(after)))
        out = script("09.routes_id_PUT.sh", [SIMPLE])
        c.check("09 prints the description before, and a default one is set",
                "is now: A new description" in out and route(ids["simple"])["description"] == "Changed by 09.routes_id_PUT.sh", out[-300:])
        script("09.routes_id_PUT.sh", [SIMPLE, 'say "hi" \\ done & <b>'])
        c.check("09 quotes, a backslash and markup are stored as typed", route(ids["simple"])["description"] == 'say "hi" \\ done & <b>')
        before = route(ids["composite"])
        script("09.routes_id_PUT.sh", [COMPOSITE, "composite text"])
        after = route(ids["composite"])
        c.check("09 a composite route keeps its template, account, subscription and its ExecuteRoute step",
                after["description"] == "composite text" and shape(after) == shape(before) and after["steps"][0]["executeRoute"] == ids["simple"],
                (shape(before), shape(after)))
        script("09.routes_id_PUT.sh", [TEMPLATE, "template text"])
        c.check("09 a template can be replaced too", route(ids["template"])["description"] == "template text")
        out = script("09.routes_id_PUT.sh", ["example_routes_nope"], expect_rc=1)
        script("09.routes_id_PUT.sh", expect_rc=2)

        # 10 PATCH
        before = route(ids["simple"])
        out = script("10.routes_id_PATCH.sh", [SIMPLE, "Rename"])
        after = route(ids["simple"])
        c.check("10 the Rename step, at position 1, is disabled; the first step and the description are untouched",
                [s["status"] for s in after["steps"]] == ["ENABLED", "DISABLED"] and after["description"] == before["description"]
                and "is at position 1, and is ENABLED" in out, out[-300:])
        script("10.routes_id_PATCH.sh", [SIMPLE, "Rename", "ENABLED"])
        c.check("10 and enabled again, with a status given", [s["status"] for s in route(ids["simple"])["steps"]] == ["ENABLED", "ENABLED"])
        script("10.routes_id_PATCH.sh", [SIMPLE, "Compress"])
        c.check("10 the first step is position 0", [s["status"] for s in route(ids["simple"])["steps"]] == ["DISABLED", "ENABLED"])
        script("10.routes_id_PATCH.sh", [COMPOSITE, "ExecuteRoute"])
        c.check("10 a composite route's ExecuteRoute step is reached the same way",
                route(ids["composite"])["steps"][0]["status"] == "DISABLED" and route(ids["composite"])["steps"][0]["executeRoute"] == ids["simple"])
        out = script("10.routes_id_PATCH.sh", [SIMPLE, "SendToPartner"], expect_rc=1)
        c.check("10 a step type the route has not is refused, nothing sent", "has no step of type SendToPartner" in out, out[-200:])
        script("10.routes_id_PATCH.sh", [SIMPLE, "Rename", "MAYBE"], expect_rc=2)
        script("10.routes_id_PATCH.sh", [SIMPLE], expect_rc=2)

    # What the notes of 10 say, with the raw calls
    sid = route(ids["simple"])["steps"][1]["id"]
    r = admin.patch("routes/" + ids["simple"], [{"op": "replace", "path": "/steps/%s/status" % sid, "value": "ENABLED"}])
    c.check("a step's id is not an address in a patch: 400", r.status == 400 and "on array" in r.text, r.text[:200])
    r = admin.patch("routes/" + ids["simple"], [{"op": "replace", "path": "/steps/9/status", "value": "ENABLED"}])
    c.check("a position past the end is 400", r.status == 400 and "out of bounds" in r.text, r.text[:200])
    r = admin.patch("routes/" + ids["simple"], [{"op": "replace", "path": "/type", "value": "TEMPLATE"}])
    c.check("type is read only", r.status == 400, r.text[:200])
    r = admin.patch("routes/" + ids["composite"], [{"op": "replace", "path": "/routeTemplate", "value": ids["template2"]}])
    c.check("a composite route's template cannot be changed", r.status == 400 and "Cannot change the Template" in r.text, r.text[:200])
    r = admin.patch("routes/" + ids["simple"], [{"op": "add", "path": "/steps/1", "value": step("middle.zip")}])
    steps = route(ids["simple"])["steps"]
    c.check("an add at /steps/1 inserts in the middle, and the precedingStep links follow",
            r.status == 204 and [s.get("outputFileName") for s in steps] == [None, "middle.zip", "renamed.zip"]
            and steps[1]["precedingStep"] == steps[0]["id"] and steps[2]["precedingStep"] == steps[1]["id"],
            [(s.get("outputFileName"), s.get("precedingStep")) for s in steps])
    r = admin.patch("routes/" + ids["simple"], [{"op": "remove", "path": "/steps/1"}])
    c.check("a remove at /steps/1 takes it out again", r.status == 204 and len(route(ids["simple"])["steps"]) == 2)

    # A route that is run by another cannot be deleted; deleting the one that runs it deletes it too
    r = admin.delete("routes/" + ids["simple"])
    c.check("a simple route that the composite route runs cannot be deleted", r.status == 400 and "in use" in r.text, r.text[:200])
    c.check("deleting the composite route succeeds", admin.delete("routes/" + ids.pop("composite")).status == 204)
    c.check("... and the simple route it ran is gone with it", admin.get("routes/" + ids["simple"]).status == 404)
    ids.pop("simple")
finally:
    for key in ("composite", "duplicate", "simple", "template", "template2"):
        if key in ids:
            admin.delete("routes/" + ids[key])
    for leftover in by_name("example_routes_*"):
        admin.delete("routes/" + leftover["id"])
    if "subscription" in ids:
        admin.delete("subscriptions/" + ids["subscription"])
    admin.delete("applications/" + APPLICATION)
    admin.delete("accounts/" + ACCOUNT)
    c.check("nothing is left behind: no example_routes_* route, and the route count is as before",
            not by_name("example_routes_*") and
            (admin.get("routes", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount") == routes_before)
    c.check("no account, application or subscription is left", not admin.exists("accounts/" + ACCOUNT) and not admin.exists("applications/" + APPLICATION))
    admin.logout()

sys.exit(c.done())
