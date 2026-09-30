#!/usr/bin/env python3
"""
Run the python examples against a fake SecureTransport and check what they do.

These are the real functions out of the real scripts. Nothing is reimplemented
here, so a change to an example that breaks its behaviour fails this check.

Runs offline. Exit code 0 means clean.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import fake_st  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures")


def fixture(name):
    with open(os.path.join(FIXTURES, name)) as fh:
        return json.load(fh)


def copy(obj):
    return json.loads(json.dumps(obj))


failures = 0


# ---------------------------------------------------------------- routes
c = fake_st.Checker("stUpdateAllRoutes.py")
routes = fixture("routes.json")

ns = fake_st.load("stUpdateAllRoutes.py",
                  emailToRemove="oldteam@example.com",
                  stepTypeToUpdate="CustomStepTracking",
                  newStepHost="sentinel.example.com",
                  newStepPort="1325",
                  updateFailureEmail=True,
                  updateStepFields=True)
s = fake_st.FakeSession({"routes": copy(routes)})
total, patched = ns["stProcessSimpleRoutes"](s, "T")

c.check("walks every route", total == 3, total)
c.check("counts routes changed, not calls", patched == 1, patched)

emails = [w for w in s.writes if w[2][0]["path"] == "/failureEmailName"]
c.check("patches the route that carries the address", len(emails) == 1 and emails[0][1].endswith("/r1"))
c.check("keeps the other address",
        emails and emails[0][2][0]["value"] == "keep@example.com",
        emails[0][2][0]["value"] if emails else None)

steps = [w for w in s.writes if "/steps/" in w[2][0]["path"]]
c.check("addresses the step by its real index",
        steps and steps[0][2][0]["path"] == "/steps/1/customProperties/mHostName",
        steps[0][2][0]["path"] if steps else None)
c.check("sets both host and port",
        steps and [o["value"] for o in steps[0][2]] == ["sentinel.example.com", "1325"])
c.check("skips a matching step type with none of the fields",
        not any(w[1].endswith("/r3") for w in s.writes))
c.check("leaves a route whose address does not match",
        not any(w[1].endswith("/r2") for w in s.writes))

ns = fake_st.load("stUpdateAllRoutes.py", emailToRemove="oldteam@example.com",
                  stepTypeToUpdate="CustomStepTracking", newStepHost="h", newStepPort="1",
                  updateFailureEmail=True, updateStepFields=True, dryRun=True)
s = fake_st.FakeSession({"routes": copy(routes)})
ns["stProcessSimpleRoutes"](s, "T")
c.check("dryRun sends nothing", len(s.writes) == 0, len(s.writes))
failures += 0 if c.summary() else 1


# ------------------------------------------------------------ put on a route
print()
c = fake_st.Checker("stUpdateRouteWithPut.py")
route = fixture("composite_route.json")
new_step = {"type": "EncodingConversion", "status": "ENABLED"}

ns = fake_st.load("stUpdateRouteWithPut.py", insertAtOffset=0, stepsToInsert=[new_step])
r = copy(route)
ns["stInsertSteps"](r)
c.check("offset 0 inserts first", r["steps"][0]["type"] == "EncodingConversion")
c.check("offset 0 keeps the existing steps", [x["type"] for x in r["steps"]][1:] == ["A", "B"])

ns = fake_st.load("stUpdateRouteWithPut.py", insertAtOffset=2, stepsToInsert=[new_step])
r = copy(route)
ns["stInsertSteps"](r)
c.check("offset at the end appends", [x["type"] for x in r["steps"]] == ["A", "B", "EncodingConversion"])

ns = fake_st.load("stUpdateRouteWithPut.py", insertAtOffset=99, stepsToInsert=[new_step])
c.check("an offset past the end is refused", ns["stInsertSteps"](copy(route)) is False)

ns = fake_st.load("stUpdateRouteWithPut.py", insertAtOffset=0, stepsToInsert=[new_step])
r = copy(route)
ns["stLinkSimpleRoute"](r, "simple-99")
c.check("linking writes an ExecuteRoute step",
        r["steps"] == [{"type": "ExecuteRoute", "status": "ENABLED",
                        "autostart": False, "executeRoute": "simple-99"}])

r = copy(route)
ns["stAttachToSubscription"](r, "sub-new")
c.check("attaching keeps the existing subscription",
        r["subscriptions"] == ["sub-existing", "sub-new"], r["subscriptions"])
c.check("attaching twice is a no-op",
        ns["stAttachToSubscription"](copy(route), "sub-existing") is False)

s = fake_st.FakeSession({"routes": [copy(route)]})
r = ns["stGetRoute"](s, "T", "c1")
ns["stAttachToSubscription"](r, "sub-new")
ns["stPutRoute"](s, "T", "c1", r)
c.check("PUT sends the whole object, not a fragment",
        s.writes and s.writes[0][2].get("name") == "Composite1" and "steps" in s.writes[0][2])
failures += 0 if c.summary() else 1


# -------------------------------------------------------------- subscriptions
print()
c = fake_st.Checker("stUpdateAllSubscriptions.py")
subs = fixture("subscriptions.json")

ns = fake_st.load("stUpdateAllSubscriptions.py", subscriptionTypeToUpdate="")
s = fake_st.FakeSession({"subscriptions": copy(subs)})
total, patched = ns["stProcessSubscriptions"](s, "T")
c.check("no filter patches them all", (total, patched) == (2, 2), (total, patched))
c.check("the body mixes replace and add",
        [o["op"] for o in s.writes[0][2]] == ["replace", "add", "add", "add"])

ns = fake_st.load("stUpdateAllSubscriptions.py", subscriptionTypeToUpdate="SharedFolder")
s = fake_st.FakeSession({"subscriptions": copy(subs)})
total, patched = ns["stProcessSubscriptions"](s, "T")
c.check("a type filter narrows the run", (total, patched) == (2, 1), (total, patched))
c.check("and targets the right object", s.writes[0][1].endswith("/s1"))
failures += 0 if c.summary() else 1


# --------------------------------------------------------- shared folder report
print()
c = fake_st.Checker("stUsersPerSharedFolder.py")
ns = fake_st.load("stUsersPerSharedFolder.py")
s = fake_st.FakeSession({"applications": fixture("applications.json"),
                         "subscriptions": fixture("sf_subscriptions.json")})

apps = ns["stReadApplications"](s, "T")
c.check("collects only SharedFolder applications",
        apps == {"SF_Finance": "/data/fin", "SF_HR": "/data/hr"}, apps)

accts, seen = ns["stProcessSubscriptions"](s, "T")
c.check("groups accounts by application", sorted(accts["SF_Finance"]) == ["alice", "bob"], accts)
c.check("ignores a non SharedFolder subscription", "dave" not in accts.get("SF_Finance", []))
c.check("records the folder the user sees", seen["SF_Finance"] == {"Finance"}, seen)
c.check("spots a subscription with no matching application",
        "SF_Gone" in accts and "SF_Gone" not in apps)
c.check("keeps an application that nobody subscribes to",
        "SF_HR" in apps and "SF_HR" not in accts)
failures += 0 if c.summary() else 1


# ----------------------------------------------------- certificate expiry dates
print()
c = fake_st.Checker("stCertificateExpiry.py")
ns = fake_st.load("stCertificateExpiry.py", expiryFieldName="",
                  expiryFieldCandidates=["endDate", "validTo", "notAfter",
                                         "expiryDate", "expirationDate",
                                         "certificateEndDate"])
import datetime  # noqa: E402
parse = ns["parseExpiry"]
find = ns["findExpiryField"]

c.check("ISO with Z", parse("2026-06-01T00:00:00Z") == datetime.datetime(2026, 6, 1))
c.check("ISO with milliseconds kept",
        parse("2026-06-01T00:00:00.123Z").replace(microsecond=0) == datetime.datetime(2026, 6, 1))
c.check("date only", parse("2026-06-01") == datetime.datetime(2026, 6, 1))
c.check("epoch milliseconds", parse(1780000000000).year == 2026)
c.check("epoch seconds", parse(1780000000).year == 2026)
c.check("epoch as a string matches the integer", parse("1780000000000") == parse(1780000000000))
c.check("None stays None", parse(None) is None)
c.check("garbage stays None", parse("not a date") is None)
c.check("an absurd number does not raise", parse(9 ** 30) is None)
c.check("finds the first candidate present", find({"notAfter": "x", "endDate": "y"}) == "endDate")
c.check("skips a null value", find({"endDate": None, "validTo": "2026-01-01"}) == "validTo")
c.check("returns None when no candidate is present", find({"name": "c"}) is None)
failures += 0 if c.summary() else 1


print()
if failures:
    print("test_python_logic: FAIL (%d group(s))" % failures)
    sys.exit(1)
print("test_python_logic: PASS")
