#!/usr/bin/env python3
"""
WRITES TO THE SERVER: runs the real, unmodified 31.RouteStepsCharsets/01
example against /routeStepsCharsets, a read only resource, and creates (then
deletes) throwaway routes named "example_charset_*" to show what the list
means for a route step. Needs --write and st_allow_writes="yes". Any route left
behind is removed in a finally block, and the check refuses to start when such
a route exists.

It shows what the example teaches and the reference does not say:
  - the answer is one object, {"charsets": [...]}, of unique names sorted
    ignoring case, with the charsets the steps use and the EBCDIC pages;
  - the example lists them, finds a name exactly, and says when a name differs
    only in case;
  - every inputCharset and outputCharset in the 17 minimal steps that
    30.RouteStepsMetadata/01 prints is in the list (`01 step FILE` says so);
  - a route step with a name outside the list: the server refuses a charset
    Java does not know (400 "not supported") and an empty one (400 "illegal"),
    for every step type that has a charset, but accepts `utf-8`, `UTF8` and
    `ASCII`, which are not in the list, and stores them as written. So the
    list is a safe set, not the whole accepted set, and `01 step FILE` is
    stricter than the server;
  - GET and HEAD only; no filter (name=, limit=, fields= are ignored); JSON only.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the charsets check (it creates and deletes throwaway routes)")

c = st_client.Checker("Route steps charsets, run for real from Admin/API 2.0/bash/31.RouteStepsCharsets (01)")
BASH = runner.path("Admin", "API 2.0", "bash")
SCRIPT = os.path.join(BASH, "31.RouteStepsCharsets", "01.routeStepsCharsets_GET.sh")
METADATA = os.path.join(BASH, "30.RouteStepsMetadata", "01.routeStepsMetadata_GET.sh")
PREFIX = "example_charset_"
SCRATCH = harness.scratch("example_charset_")


def script(args=None, expect_rc=0):
    return harness.run_script(c, os.path.dirname(SCRIPT), os.path.basename(SCRIPT), args, expect_rc,
                              label=lambda name, shown, rc: "01 %s exits %s" % (shown or "with no arguments", rc))


def write_json(name, value):
    path = os.path.join(SCRATCH, name)
    with open(path, "w") as f:
        json.dump(value, f)
    return path


def left_over():
    found = (admin.get("routes", params={"name": PREFIX + "*"}).json() or {}).get("result") or []
    return [r for r in found if r.get("name", "").startswith(PREFIX)]


def route_with_step(label, step):
    return {"type": "SIMPLE", "name": PREFIX + label, "conditionType": "ALWAYS", "condition": True, "steps": [step]}


def errors_of(response):
    return " ".join((response.json() or {}).get("validationErrors") or [])


admin = harness.connect(config, c, mock="the bundled mock does not implement /routeStepsCharsets")
if left_over():
    c.check("no route named %s* exists yet" % PREFIX, False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

try:
    with runner.real_credentials(BASH, config):
        answer = admin.get("routeStepsCharsets")
        data = answer.json()
        names = data.get("charsets") if isinstance(data, dict) else None
        c.check("the answer is one object with a charsets array, not a plain array",
                answer.status == 200 and isinstance(names, list) and list(data) == ["charsets"], str(data)[:100])
        names = names or []
        c.check("the charsets are strings, all different", all(isinstance(n, str) for n in names) and len(set(names)) == len(names))
        c.check("the list is sorted ignoring case", names == sorted(names, key=str.lower))
        c.check("it holds what the minimal steps use and the EBCDIC pages",
                {"UTF-8", "UTF-16", "US-ASCII", "ISO-8859-1", "windows-1252", "IBM037"} <= set(names))
        c.info("%d charsets" % len(names))

        # The example
        out = script()
        c.check("01 counts the charsets", "Character sets: %d" % len(names) in out, out[:80])
        c.check("01 lists every name, one per line", all(("\n  %s\n" % n) in out + "\n" for n in names), out[-200:])
        out = script(["UTF-8"])
        c.check("01 a listed name is found", "UTF-8 is in the list." in out, out)
        out = script(["utf-8"], expect_rc=1)
        c.check("01 a name that differs only in case is not found as written, and the spelling is shown",
                "utf-8 is not in the list as written; the list has UTF-8." in out, out)
        out = script(["NOPE-9"], expect_rc=1)
        c.check("01 an unknown name is not in the list", "NOPE-9 is not in the list." in out, out)
        out = script(["step"], expect_rc=2)
        c.check("01 step with no file is a usage error", "Usage:" in out, out)

        # Every charset of the 30 minimal steps is in the list
        types = [s["stepType"] for s in admin.get("routeStepsMetadata").json()]
        minimal = []
        for step_type in types:
            result = runner.run(METADATA, [step_type, "minimal"], timeout=60)
            if result.returncode == 0:
                minimal.append(json.loads(result.stdout))
        c.check("30.RouteStepsMetadata/01 gave a minimal step for every listed type", len(minimal) == len(types), "%d of %d" % (len(minimal), len(types)))
        with_charset = [s for s in minimal if "inputCharset" in s or "outputCharset" in s]
        c.check("6 of the minimal steps name a charset (EncodingConversion two)",
                sorted(s["type"] for s in with_charset) == sorted(
                    ["CharactersReplace", "EncodingConversion", "LineEnding", "LineFolding", "LinePadding", "LineTruncating"]),
                str([s["type"] for s in with_charset]))
        out = script(["step", write_json("minimal_steps.json", minimal)])
        wanted = sum(("inputCharset" in s) + ("outputCharset" in s) for s in minimal)
        c.check("01 step: all %d charsets of the %d minimal steps are listed" % (wanted, len(minimal)),
                out.count(": listed") == wanted and "NOT listed" not in out, out[-500:])
        c.check("01 step: EncodingConversion's two are named by position, type and field",
                any(" EncodingConversion inputCharset UTF-8: listed" in l for l in out.splitlines())
                and any(" EncodingConversion outputCharset UTF-16: listed" in l for l in out.splitlines()), out[-500:])
        encoding = next(s for s in minimal if s["type"] == "EncodingConversion")
        out = script(["step", write_json("route.json", route_with_step("file", encoding))])
        c.check("01 step: a route with a steps array is read the same way", out.count(": listed") == 2, out)
        out = script(["step", write_json("step.json", dict(encoding, outputCharset="UTF8"))], expect_rc=1)
        c.check("01 step: a charset outside the list is marked NOT listed, exit 1",
                "  step 0 EncodingConversion outputCharset UTF8: NOT listed" in out, out)
        out = script(["step", write_json("compress.json", next(s for s in minimal if s["type"] == "Compress"))])
        c.check("01 step: a step with no charset has nothing to check, exit 0", "nothing to check" in out, out)

        # The server's own rule for a route step, against the list
        base = dict(encoding)
        for field in ("inputCharset", "outputCharset"):
            r = admin.post("routes", route_with_step("bogus", dict(base, **{field: "NOPE-9"})))
            c.check("a %s that Java does not know is refused: 400 'not supported'" % field,
                    r.status == 400 and "The charset specified by %s is not supported" % field in errors_of(r),
                    "%s %s" % (r.status, errors_of(r)))
            r = admin.post("routes", route_with_step("empty", dict(base, **{field: ""})))
            c.check("an empty %s is refused: 400 'illegal'" % field,
                    r.status == 400 and "The charset name specified by %s is illegal" % field in errors_of(r),
                    "%s %s" % (r.status, errors_of(r)))
        for step in (s for s in minimal if s["type"] != "EncodingConversion" and "inputCharset" in s):
            r = admin.post("routes", route_with_step("bogus", dict(step, inputCharset="NOPE-9")))
            c.check("%s refuses an inputCharset that is not a charset too (400)" % step["type"],
                    r.status == 400 and "inputCharset is not supported" in errors_of(r), "%s %s" % (r.status, errors_of(r)))
        outside = [n for n in ("utf-8", "UTF8", "ASCII") if n not in names]
        c.check("utf-8, UTF8 and ASCII are not in the list", outside == ["utf-8", "UTF8", "ASCII"], str(outside))
        for name in outside:
            r = admin.post("routes", route_with_step("alias", dict(base, inputCharset=name)))
            created = c.check("a name outside the list is still accepted by the server: %s is 201" % name, r.status == 201,
                              "%s %s" % (r.status, errors_of(r)))
            if created:
                route_id = r.headers.get("Location", "").rsplit("/", 1)[-1]
                got = ((admin.get("routes/" + route_id).json() or {}).get("steps") or [{}])[0]
                c.check("and stored as written: %s" % name, got.get("inputCharset") == name, str(got.get("inputCharset")))
                admin.delete("routes/" + route_id)

        # The endpoint itself
        c.check("name=, limit=, offset= and fields= are ignored: the whole list is answered",
                all((admin.get("routeStepsCharsets", params=p).json() or {}).get("charsets") == names
                    for p in ({"name": "UTF-8"}, {"limit": 2}, {"offset": 5}, {"fields": "x"})))
        c.check("HEAD is 200", admin.head("routeStepsCharsets").status == 200)
        c.check("POST, PUT, PATCH and DELETE are 405",
                [admin.post("routeStepsCharsets", {}).status, admin.put("routeStepsCharsets", {}).status,
                 admin.patch("routeStepsCharsets", []).status, admin.delete("routeStepsCharsets").status] == [405] * 4)
        c.check("there is no read of one charset: /routeStepsCharsets/UTF-8 is 404", admin.get("routeStepsCharsets/UTF-8").status == 404)
        c.check("XML and CSV are 406",
                [admin._request("GET", "routeStepsCharsets", extra_headers={"Accept": a}).status
                 for a in ("application/xml", "text/csv")] == [406, 406])
finally:
    for route in left_over():
        admin.delete("routes/" + route["id"])
    c.check("nothing is left behind: no route named %s*" % PREFIX, not left_over())
    admin.logout()

sys.exit(c.done())
