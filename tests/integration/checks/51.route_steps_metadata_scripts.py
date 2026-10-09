#!/usr/bin/env python3
"""
WRITES TO THE SERVER: runs the real, unmodified 30.RouteStepsMetadata/01
example, then creates, reads back and deletes a throwaway route
("example_meta_<type>") for each step type the server lists, with the smallest
step of that type, which the example prints with `01 <type> minimal`. Needs
--write and st_allow_writes="yes". Any route left behind is removed in a
finally block, and the check refuses to start when such a route exists.

It shows what the example teaches and the reference does not say:
  - the answer is a plain array of entries with 12 keys, and every `stepType`
    is accepted as the `type` of a route step, but the metadata does not say
    which fields a step needs: the server does, in validationErrors;
  - the minimal step the example prints for each of the 17 types is accepted
    (201), reads back with the type and every field it was given, and is
    minimal: leaving out any one of its fields is 400. None of the 17 needs an
    object that exists on the server (an account, a site, a PGP key), because
    creating a route does not look them up;
  - a type that is not in the list is refused with "Route Step type is
    undefined.";
  - the filters of the reference's neighbours (stepType=, limit=) are ignored,
    fields= keeps the keys named, the answer is JSON only (XML 406) and
    nothing but GET and HEAD works.

A type for which the example keeps no minimal step is only checked with an
incomplete step (a 400 that names the fields, not "undefined"), and the check
says so. On the lab all 17 have one, so none is.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the step types check (it creates and deletes throwaway routes)")

c = st_client.Checker("Route steps metadata, run for real from Admin/API 2.0/bash/30.RouteStepsMetadata (01)")
SCRIPT = os.path.join(runner.path("Admin", "API 2.0", "bash"), "30.RouteStepsMetadata", "01.routeStepsMetadata_GET.sh")
PREFIX = "example_meta_"
KEYS = {"stepType", "stepCategory", "stepDisplayName", "endpointSchema", "uiPagePath", "stepPropertyBean",
        "stepValidatorClassName", "routeBuilderClassName", "stepPropertyTransformer", "stepModule",
        "stepProducer", "stepJarName"}


def script(args=None, expect_rc=0):
    return harness.run_script(c, os.path.dirname(SCRIPT), os.path.basename(SCRIPT), args, expect_rc,
                              label=lambda name, shown, rc: "01 %s exits %s" % (shown or "with no arguments", rc))


def left_over():
    found = (admin.get("routes", params={"name": PREFIX + "*"}).json() or {}).get("result") or []
    return [r for r in found if r.get("name", "").startswith(PREFIX)]


def route_with_step(step):
    return {"type": "SIMPLE", "name": PREFIX + step["type"], "conditionType": "ALWAYS", "condition": True, "steps": [step]}


def errors_of(response):
    return (response.json() or {}).get("validationErrors") or []


def read_back_differs(sent, got):
    """The fields of the step sent that the step read back does not hold as sent."""
    differs = []
    for key, value in sent.items():
        if key == "actionOnStepFailure" and sent["type"] == "setflowattributes":
            held = (got.get("customProperties") or {}).get(key)  # this type keeps it among its custom properties
        else:
            held = got.get(key)
        if str(held) != str(value):  # linePaddingLength is a number sent and a string read back
            differs.append("%s: sent %r, read %r" % (key, value, held))
    return differs


admin = harness.connect(config, c, mock="the bundled mock does not implement /routeStepsMetadata")
if left_over():
    c.check("no route named %s* exists yet" % PREFIX, False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

try:
    steps = admin.get("routeStepsMetadata").json()
    types = [s["stepType"] for s in steps] if isinstance(steps, list) else []
    c.check("the answer is a plain array of step types", isinstance(steps, list) and len(types) > 0, str(steps)[:200])
    c.check("every entry has the same 12 keys", all(set(s) == KEYS for s in steps), str([sorted(s) for s in steps][:1]))
    c.check("every entry has a category, Transformation or Routing",
            all(s["stepCategory"] in ("Transformation", "Routing") for s in steps))
    c.check("the step types are unique", len(set(types)) == len(types))
    c.check("Compress and SendToPartner, which 09.CompositeRoutes uses, are listed", {"Compress", "SendToPartner"} <= set(types))
    c.check("ExecuteRoute, the composite route's step, is not listed", "ExecuteRoute" not in types)

    # The example itself
    out = script()
    c.check("01 counts the step types", "Route step types: %d" % len(steps) in out, out[:120])
    c.check("01 lists every type with its category and display name",
            all("  %s  %s  %s" % (s["stepCategory"], s["stepType"], s["stepDisplayName"]) in out for s in steps), out[-600:])
    out = script(["Compress"])
    c.check("01 a type given shows its whole entry", '"endpointSchema": "st.compress"' in out and "Rename" not in out, out[-300:])
    out = script(["compress"], expect_rc=1)
    c.check("01 the type is case sensitive, and a miss says so", "Not a step type of this server" in out, out[-200:])

    # What the example's Notes claim about the endpoint
    kept = admin.get("routeStepsMetadata", params={"fields": "stepType"}).json()
    c.check("fields= keeps the keys named", all(set(s) == {"stepType"} for s in kept) and len(kept) == len(steps))
    nothing = admin.get("routeStepsMetadata", params={"fields": "nosuchfield"}).json()
    c.check("an unknown field gives empty objects", nothing == [{}] * len(steps), str(nothing)[:100])
    c.check("stepType= is ignored, every type is answered",
            len(admin.get("routeStepsMetadata", params={"stepType": types[0]}).json()) == len(steps))
    c.check("limit= is ignored", len(admin.get("routeStepsMetadata", params={"limit": 1}).json()) == len(steps))
    c.check("XML is 406", admin._request("GET", "routeStepsMetadata", extra_headers={"Accept": "application/xml"}).status == 406)
    c.check("HEAD is 200", admin.head("routeStepsMetadata").status == 200)
    c.check("POST, PUT and DELETE are 405",
            [admin.post("routeStepsMetadata", {}).status, admin.put("routeStepsMetadata", {}).status,
             admin.delete("routeStepsMetadata").status] == [405, 405, 405])
    c.check("there is no read of a single type: /routeStepsMetadata/Compress is 404",
            admin.get("routeStepsMetadata/Compress").status == 404)

    # The stepType is the type of a route step, and the example prints the smallest step of each
    incomplete_only = []
    for step_type in types:
        result = runner.run(SCRIPT, [step_type, "minimal"], timeout=60)
        if result.returncode != 0:
            incomplete_only.append(step_type)
            step = {"type": step_type, "status": "ENABLED", "conditionType": "ALWAYS"}
            r = admin.post("routes", route_with_step(step))
            c.check("a step of type %s, kept only as an incomplete step (the example has no minimal one), "
                    "is checked against that type: 400 naming fields, not 'undefined'" % step_type,
                    r.status == 400 and errors_of(r) and not any("undefined" in e for e in errors_of(r)),
                    "%s %s" % (r.status, r.text[:200]))
            continue
        try:
            step = json.loads(result.stdout)
        except ValueError:
            step = None
        if not c.check("01 %s minimal prints one JSON step of that type" % step_type,
                       isinstance(step, dict) and step.get("type") == step_type, result.stdout[:200]):
            continue
        r = admin.post("routes", route_with_step(step))
        created = c.check("the smallest %s step is accepted: POST /routes is 201" % step_type, r.status == 201,
                          "%s %s" % (r.status, r.text[:300]))
        if created:
            route_id = r.headers.get("Location", "").rsplit("/", 1)[-1]
            route = admin.get("routes/" + route_id).json() or {}
            got = (route.get("steps") or [{}])[0]
            c.check("%s reads back from GET /routes/{id} with its type and every field as sent" % step_type,
                    len(route.get("steps") or []) == 1 and not read_back_differs(step, got),
                    "; ".join(read_back_differs(step, got))[:300])
            admin.delete("routes/" + route_id)
        # Minimal: each field the example gives is needed, so leaving any one out is 400
        needed = [k for k in step if k != "type"]
        unneeded = []
        for field in needed:
            r = admin.post("routes", route_with_step({k: v for k, v in step.items() if k != field}))
            if r.status == 201:
                unneeded.append(field)
                admin.delete("routes/" + r.headers.get("Location", "").rsplit("/", 1)[-1])
        c.check("the smallest %s step is minimal: leaving out any one of %d fields is 400" % (step_type, len(needed)),
                not unneeded, "accepted without: %s" % unneeded)
    if incomplete_only:
        c.info("only checked with an incomplete step: %s" % ", ".join(incomplete_only))
    else:
        c.info("every listed type was created for real: none needed an outside object, so none is checked only "
               "with an incomplete step")
    r = admin.post("routes", route_with_step({"type": "Compress", "status": "ENABLED", "conditionType": "ALWAYS"}))
    c.check("an incomplete Compress step names the fields it lacks, such as compressionType (400)",
            r.status == 400 and "steps[0].compressionType must not be null" in errors_of(r), str(errors_of(r)))
    r = admin.post("routes", route_with_step({"type": "NoSuchStepType", "status": "ENABLED", "conditionType": "ALWAYS"}))
    c.check("a type that is not listed is refused: Route Step type is undefined.",
            r.status == 400 and any("Route Step type is undefined" in e for e in errors_of(r)),
            "%s %s" % (r.status, r.text[:200]))
finally:
    for route in left_over():
        admin.delete("routes/" + route["id"])
    c.check("nothing is left behind: no route named %s*" % PREFIX, not left_over())
    admin.logout()

sys.exit(c.done())
