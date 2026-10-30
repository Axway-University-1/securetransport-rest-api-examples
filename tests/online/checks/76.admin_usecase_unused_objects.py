#!/usr/bin/env python3
"""
WRITES TO THE SERVER (two accounts, two certificates, four sites, two transfer profiles, two applications, two subscriptions, two route templates, four simple routes and two composite routes, all named
example_unu_*, and one uploaded file; it removes the objects, and the transfer and the server log keep their entries). Runs Admin/UseCases/08-identify-unused-objects for real, as the administrator of the configuration.

It proves what the use case and its README say, through its own calls and not through the scripts:
  - the relationships: the site names the certificate by id; the subscription names its application, site and transfer profile by name; the composite route has the template id, the subscription id and
    three steps (enabled, enabled, disabled) that run the three simple routes by id; a simple route has no account and no template; a second step that runs the same simple route is refused (400);
    a transfer profile is refused for an account that has no PeSIT site; a composite route needs no step;
  - the experiment: after one upload, the server log names the composite route by name and the simple routes that ran by their id (AR0011, AR0108), never by name, and names the route of the disabled
    step in no way at all; a search finds itself (the entries that hold /api/v2.0/); the entries are in the log within the wait;
  - the disabled step: step 06 changes the status of one step and nothing else, and the log still names that route;
  - the map and its cost: 8 calls and 22 objects for the demo set, as the README says;
  - the answer: step 09 lists the ten objects that were built to be unused, grouped by type, and not one more, keeps rt_old, and the used ones are not in it; step 10 reads only (GET) and finds the same ten
    among the objects of the whole server, with its cost;
  - the cleanup: nothing named example_unu_* is left, the simple routes went with their composite route, and the log still names the routes that ran.
Then it runs 00.run_all.sh once more as a whole.

Needs --write and st_allow_writes="yes". Takes about 2 minutes: run it with ST_CHECK_TIMEOUT=900. It does not run on the bundled mock.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the identify unused objects use case for real")

c = st_client.Checker("Admin use case 08-identify-unused-objects, run for real")

UC = runner.path("Admin", "UseCases", "08-identify-unused-objects")
ENV = {"ST_ENDUSER_PORT": harness.ports(config).enduser}
STATE = ("session.cookie.jar", "state.local.csrf", "state.local.password", "state.local.map", "state.local.mapall")
P = "example_unu_"
EXPECTED = sorted(["Account|" + P + "a2", "Application|" + P + "app_unused", "Certificate|" + P + "cert_unused", "Composite route|" + P + "comp_unused", "Route|" + P + "rt_never",
                   "Route|" + P + "rt_orphan", "Route template|" + P + "tpl_unused", "Site|" + P + "site_unused", "Subscription|" + P + "a1 /example_unu_sub_unused",
                   "Transfer profile|" + P + "profile_unused"])

admin = harness.connect(config, c, mock="the bundled mock has no routes, certificates or server log; run this against a real server to exercise it")


def clear_local():
    for leftover in STATE:
        p = os.path.join(UC, leftover)
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p, topdown=False):
                for f in files:
                    os.remove(os.path.join(root, f))
                os.rmdir(root)
        elif os.path.exists(p):
            os.remove(p)


def script(name, *args, timeout=400):
    return runner.run(os.path.join(UC, name), list(args), timeout=timeout, env=ENV)


def one(resource, name):
    found = [o for o in admin.results(resource, {"name": name, "limit": 100}) if o.get("name") == name]
    return found[0] if found else None


def leftovers():
    left = []
    for resource in ("accounts", "applications", "certificates", "sites", "transferProfiles", "routes"):
        left += [resource + "/" + o["name"] for o in admin.results(resource, {"name": P + "*", "limit": 100}) if o.get("name")]
    return left


def log_entries(text):
    """The entries of the server log that hold the text, apart from the administrator's own requests (they hold the text that was asked for)."""
    answer = admin.get("logs/server", {"message": text, "limit": 100}).json() or {}
    entries = answer.get("result") or []
    real = [e for e in entries if "/api/v2.0/" not in (e.get("message") or "")]
    return real, [e for e in entries if "/api/v2.0/" in (e.get("message") or "")]


def parse_unused(text):
    """'Type|name' for each line of the unused objects of the output (the lines under 'Unused objects', before 'Total:')."""
    found, kind = [], None
    for line in text.split("Unused objects", 1)[-1].splitlines():
        if line.startswith("Total:"):
            break
        m = re.match(r"^  ([A-Z][A-Za-z ]*) \(\d+\)$", line)
        if m:
            kind = m.group(1)
            continue
        m = re.match(r"^    (.+?)  \(.*\)$", line)
        if m and kind:
            found.append(kind + "|" + m.group(1))
    return sorted(found)


try:
    if leftovers():
        c.info("objects named example_unu_* are on the server already (%s); skipping rather than reuse them" % ", ".join(leftovers()))
        admin.logout()
        sys.exit(c.done())

    # ================= steps 01 to 04: the objects and the relationships ===========================================================
    for step in ("01.accounts_certificates_POST.sh", "02.partnerships_POST.sh", "03.subscriptions_POST.sh", "04.routes_POST.sh"):
        r = script(step)
        c.check("%s: exit 0" % step, r.returncode == 0, (r.returncode, r.stdout[-400:]))
        if r.returncode != 0:
            raise SystemExit(c.done())
    cert_used, cert_unused = one("certificates", P + "cert_used"), one("certificates", P + "cert_unused")
    c.check("01: the two certificates are private and owned by a1", cert_used and cert_unused and cert_used.get("usage") == "private" and cert_used.get("account") == P + "a1" and cert_unused.get("account") == P + "a1", (cert_used, cert_unused))
    site_used = one("sites", P + "site_used")
    c.check("02: the site names its certificate by id (clientCertificate)", site_used and site_used.get("clientCertificate") == cert_used["id"], site_used and site_used.get("clientCertificate"))
    c.check("02: the other sites have no certificate", all(not (one("sites", P + n) or {}).get("clientCertificate") for n in ("site_step", "site_unused")))
    c.check("02: the PeSIT site is there (a transfer profile needs one) and so are the two transfer profiles", one("sites", P + "pesit_support") and one("transferProfiles", P + "profile_used") and one("transferProfiles", P + "profile_unused"))
    refused = admin.post("transferProfiles", {"name": P + "profile_x", "account": P + "a2", "sendMapping": "/*", "fileLabelOption": "DONT_SEND"})
    c.check("02: a transfer profile for an account with no PeSIT site is refused (400 'Account does not contain any PeSIT transfer sites.')", refused.status == 400 and "does not contain any PeSIT transfer sites" in refused.text, (refused.status, refused.text[:200]))
    subs = admin.results("subscriptions", {"account": P + "a1", "limit": 100})
    sub = next((s for s in subs if s.get("folder") == "/example_unu_in"), {})
    cfg = (sub.get("transferConfigurations") or [{}])[0]
    c.check("03: the subscription names application, site and transfer profile by name", sub.get("application") == P + "app_used" and cfg.get("site") == P + "site_used" and cfg.get("transferProfile") == P + "profile_used", sub)
    unused_sub = next((s for s in subs if s.get("folder") == "/example_unu_sub_unused"), {})
    c.check("03: the second subscription has nothing attached", unused_sub and not unused_sub.get("transferConfigurations"), unused_sub)
    comp, comp2 = one("routes", P + "comp_used"), one("routes", P + "comp_unused")
    tpl = one("routes", P + "tpl_used")
    simple = {n: one("routes", P + n) for n in ("rt_on", "rt_old", "rt_never", "rt_orphan")}
    c.check("04: the composite route has the template id, the subscription id, and three steps that run the three simple routes by id: enabled, enabled, disabled",
            comp and comp.get("routeTemplate") == tpl["id"] and comp.get("subscriptions") == [sub["id"]] and [s["status"] for s in comp["steps"]] == ["ENABLED", "ENABLED", "DISABLED"]
            and [s["executeRoute"] for s in comp["steps"]] == [simple["rt_on"]["id"], simple["rt_old"]["id"], simple["rt_never"]["id"]], comp)
    c.check("04: the unused composite route has no step and no subscription", comp2 and not comp2.get("steps") and not comp2.get("subscriptions"), comp2)
    c.check("04: a simple route has no account and no template", all(not s.get("account") and not s.get("routeTemplate") for s in simple.values()), simple["rt_on"])
    c.check("04: the orphan's step names the site as SITE#!#CVD#!#", simple["rt_orphan"]["steps"][0].get("transferSiteExpression") == P + "site_step#!#CVD#!#", simple["rt_orphan"]["steps"][0].get("transferSiteExpression"))
    second = admin.post("routes", {"name": P + "comp_x", "type": "COMPOSITE", "account": P + "a1", "conditionType": "MATCH_ALL", "routeTemplate": tpl["id"],
                                   "steps": [{"type": "ExecuteRoute", "status": "ENABLED", "autostart": False, "executeRoute": simple["rt_on"]["id"]}]})
    c.check("04: a second step that runs the same simple route is refused (400)", second.status == 400 and "cannot be referenced more that once" in second.text, (second.status, second.text[:200]))

    # ================= step 05: the experiment =====================================================================================
    r = script("05.upload_POST.sh", "90")
    c.check("05: exit 0, the upload ran and the log named the routes within the wait", r.returncode == 0 and "The log has them," in r.stdout, (r.returncode, r.stdout[-600:]))
    on_real, on_echo = log_entries(simple["rt_on"]["id"])
    old_real, _ = log_entries(simple["rt_old"]["id"])
    never_real, never_echo = log_entries(simple["rt_never"]["id"])
    c.check("log: the route that an enabled step ran is named by its id (AR0011, the sandbox of its execution)", on_real and any(e["message"].startswith("AR0011") for e in on_real), [e["message"][:80] for e in on_real])
    c.check("log: the second enabled route too", old_real and any(e["message"].startswith("AR0011") for e in old_real))
    step_id = simple["rt_on"]["steps"][0]["id"]
    step_real, _ = log_entries(step_id)
    c.check("log: its step is named by id too: 'Step {Compress} with id {...} is starting' (AR0108)", any(e["message"].startswith("AR0108") and step_id in e["message"] for e in step_real), [e["message"][:80] for e in step_real])
    c.check("log: the route of the DISABLED step is named by nothing: no entry but the administrator's own requests, by id", never_real == [], [e["message"][:80] for e in never_real])
    never_step_real, _ = log_entries(simple["rt_never"]["steps"][0]["id"])
    c.check("log: nor is its step", never_step_real == [])
    c.check("log: a search finds itself: the entries that hold /api/v2.0/ are the administrator's requests for the search", len(never_echo) >= 2, len(never_echo))
    name_real, _ = log_entries(simple["rt_on"]["name"])
    c.check("log: by NAME the simple route is found only at its creation and in the requests, never in the run (no entry says AR0011 or AR0108 for the name)",
            not any(e["message"].startswith(("AR0011", "AR0108")) for e in name_real), [e["message"][:80] for e in name_real])
    comp_real, _ = log_entries("[" + P + "comp_used]")
    c.check("log: the composite route is named in every line of the run, by name", sum(1 for e in comp_real if e["message"].startswith("AR")) >= 5, len(comp_real))
    uploaded = re.search(r"of /example_unu_in/(hello_\d+\.txt) as", r.stdout) or re.search(r"(hello_\d+\.txt)", r.stdout)
    transfers = [e for e in admin.results("logs/transfers", {"account": P + "a1", "limit": 100}) if uploaded and e.get("filename") == uploaded.group(1)]
    c.check("05: the transfer log has the upload: one entry, inbound, with the application and the site of the subscription",
            len(transfers) == 1 and transfers[0].get("incoming") is True and transfers[0].get("application") == P + "app_used" and (transfers[0].get("site") or {}).get("name") == P + "site_used",
            [(e.get("filename"), e.get("incoming"), e.get("application")) for e in transfers])

    # ================= step 06 ======================================================================================================
    r = script("06.step_PATCH_disable.sh")
    comp = one("routes", P + "comp_used")
    c.check("06: exit 0, and only the step of rt_old is disabled now", r.returncode == 0 and [s["status"] for s in comp["steps"]] == ["ENABLED", "DISABLED", "DISABLED"], (r.returncode, [s["status"] for s in comp["steps"]], r.stdout[-300:]))
    c.check("06: the composite route is otherwise as it was (template, subscription, step order)", comp["routeTemplate"] == tpl["id"] and comp["subscriptions"] == [sub["id"]]
            and [s["executeRoute"] for s in comp["steps"]] == [simple["rt_on"]["id"], simple["rt_old"]["id"], simple["rt_never"]["id"]])
    c.check("06: the log still names rt_old", log_entries(simple["rt_old"]["id"])[0] != [])

    # ================= steps 07 to 09 ===============================================================================================
    r = script("07.map_relationships_GET.sh")
    m = re.search(r"^  Total\s+(\d+)\s+(\d+)\s+(\d+)$", r.stdout, re.M)
    c.check("07: exit 0, and the cost of the demo set is 8 calls and 22 objects", r.returncode == 0 and m and (m.group(1), m.group(2)) == ("8", "22"), (r.returncode, r.stdout[-500:]))
    r = script("08.server_log_search_GET.sh")
    c.check("08: exit 0, one call for each route that only disabled steps run: rt_old is found, rt_never is not", r.returncode == 0 and "%srt_old: found" % P in r.stdout and "%srt_never: not found" % P in r.stdout and "2 call(s) to the server log" in r.stdout, (r.returncode, r.stdout[-600:]))
    c.check("08: rt_on, which an enabled step runs, is not searched", "rt_on" not in r.stdout, r.stdout[-300:])
    r = script("09.unused_objects_GET.sh")
    found = parse_unused(r.stdout)
    c.check("09: exit 0, and the unused objects are exactly the ten that were built to be, grouped by type", r.returncode == 0 and found == EXPECTED, (r.returncode, sorted(set(found) ^ set(EXPECTED))))
    c.check("09: 'Total: 10 unused objects of 9 types.'", "Total: 10 unused objects of 9 types." in r.stdout)
    c.check("09: rt_old is kept, and said to have run in the past", "Kept, although disabled now (1)" in r.stdout and "%srt_old  (disabled now, but the server log names it: it ran in the past)" % P in r.stdout)
    used = [P + n for n in ("a1", "app_used", "cert_used", "comp_used", "rt_on", "tpl_used", "site_used", "site_step", "profile_used")]
    unused_part = r.stdout.split("Kept, although disabled now")[0]
    c.check("09: what is used is not in the list (the site that only a step of an orphan route names is used too)", all(("%s  (" % u) not in unused_part for u in used), [u for u in used if ("%s  (" % u) in unused_part])
    c.check("09: it says it is the list that was built", "This is the list that was built on purpose: 10 objects, no more and no fewer." in r.stdout)

    # a certificate that a site names stops being unused: change the relation through the API and read the answer again
    admin.patch("sites/" + one("sites", P + "site_unused")["id"], [{"op": "add", "path": "/clientCertificate", "value": cert_unused["id"]}])
    script("07.map_relationships_GET.sh")
    script("08.server_log_search_GET.sh")
    r = script("09.unused_objects_GET.sh")
    after = parse_unused(r.stdout)
    c.check("09: a site gets the certificate: the certificate is no longer unused (the list is no longer the one that was built, exit 1)", r.returncode == 1 and ("Certificate|" + P + "cert_unused") not in after and ("Site|" + P + "site_unused") in after, (r.returncode, sorted(set(after) ^ set(EXPECTED))))

    # ================= step 10: the whole server, read only =========================================================================
    before = {r_: len(admin.results(r_, {"name": P + "*", "limit": 100})) for r_ in ("accounts", "sites", "routes")}
    r = script("10.whole_server_GET.sh", timeout=600)
    m = re.search(r"^  Total\s+(\d+)\s+(\d+)\s+(\d+)$", r.stdout, re.M)
    whole = parse_unused(r.stdout.split("The whole server took")[0])
    c.check("10: exit 0, the cost of the whole server is printed (calls and objects)", r.returncode == 0 and m and int(m.group(1)) >= 7 and int(m.group(2)) > 22, (r.returncode, r.stdout[:500]))
    c.check("10: the demo set is found among the unused objects of the whole server: the nine that are still unused (the certificate that a site names now is not)",
            sorted(e for e in whole if P in e) == sorted(e for e in EXPECTED if e != "Certificate|" + P + "cert_unused"), [e for e in whole if P in e])
    c.check("10: it changed nothing: the objects of the demo set are as many as before", {r_: len(admin.results(r_, {"name": P + "*", "limit": 100})) for r_ in ("accounts", "sites", "routes")} == before)
    c.check("10: it only reads, and says so", "This is read only: it changes and deletes nothing." in r.stdout)

    # ================= step 99 ======================================================================================================
    ids = [s["id"] for s in simple.values()] + [comp["id"], comp2["id"], tpl["id"]]
    r = script("99.cleanup_DELETE.sh")
    c.check("99: exit 0, and nothing named example_unu_* is left", r.returncode == 0 and leftovers() == [], (r.returncode, leftovers(), r.stdout[-400:]))
    c.check("99: the simple routes went with the composite route that ran them (and the orphan, deleted by itself)", all(admin.get("routes/" + i).status == 404 for i in ids), [i for i in ids if admin.get("routes/" + i).status != 404])
    c.check("99: the log still names the route that ran", log_entries(simple["rt_old"]["id"])[0] != [])
    c.check("99: the subscriptions of a1 went with the account or were deleted", admin.results("subscriptions", {"account": P + "a1", "limit": 10}) == [])
    for leftover in STATE:
        c.check("99: no %s is left" % leftover, not os.path.exists(os.path.join(UC, leftover)))
    r = script("99.cleanup_DELETE.sh")
    c.check("99 a second time, with nothing to remove, exits 0", r.returncode == 0, r.stdout[-300:])

    # ================= the whole use case, once more ================================================================================
    r = script("00.run_all.sh", timeout=600)
    c.check("00: exit 0, ten steps and the cleanup, the list is the one that was built", r.returncode == 0 and r.stdout.count("=== ") >= 11 and "=== 99.cleanup_DELETE ===" in r.stdout
            and "This is the list that was built on purpose" in r.stdout, (r.returncode, r.stdout[-600:]))
    c.check("00: and it left nothing behind", leftovers() == [] and not any(os.path.exists(os.path.join(UC, f)) for f in STATE), leftovers())
    r = script("00.run_all.sh", "x")
    c.check("00: a parameter is exit 2 and nothing is made", r.returncode == 2 and leftovers() == [], (r.returncode, r.stdout[-200:]))
finally:
    script("99.cleanup_DELETE.sh")
    c.check("no object named example_unu_* is left on the server", leftovers() == [], leftovers())
    clear_local()
    admin.logout()

sys.exit(c.done())
