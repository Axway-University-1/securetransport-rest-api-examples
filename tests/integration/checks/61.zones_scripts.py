#!/usr/bin/env python3
"""
WRITES TO THE SERVER (throwaway zones, business units and accounts only). Runs the
real, unmodified 37.Zones examples against throwaway network zones and shows what a
zone is and what naming one changes.

  - 01 lists the zones, counts them, filters by an EXACT, case sensitive name.
  - 02 creates a zone (no edge by default; with an edge, an address and a disabled SSH
    protocol when asked); refuses a duplicate (400, not the 409 of the reference), keeps
    names that differ in case apart, and refuses bad arguments before sending anything.
  - 03 and 04 check and read one, and 04 lists the business units that name it.
  - 05 and 06 change the description, and nothing else: the zone is otherwise read back
    unchanged, a proxy password's flag and the edge ids included. The raw API: a PUT
    resets what it leaves out (publicURLPrefix, ssoSpEntityId, isDnsResolutionEnabled,
    isDefault) but keeps the edges when there is no `edges` key; a name that differs from
    the path is 400; a default zone is the only default.
  - 07 deletes one: refused with a 500 while a business unit names it, fine afterwards.
  - What naming a zone changes: an account of a business unit whose `dmz` is a zone with an
    edge logs in over SFTP and over HTTP (the EndUser API), and, as the legacy part, FTP,
    exactly as before (a standalone lab has no edge in front of it); the zone is stored on
    the unit and blocks the zone's deletion; a default zone is not copied into new units.

Never touches a zone it did not create (`Private` above all): refuses to start when a
zone named example* (in any capitals) exists, and ends by comparing the whole list of
zones with the one saved first. The accounts get a new name and user id on every run (a
home folder outlives its account). Needs --write and st_allow_writes="yes".
"""
import contextlib
import json
import os
import random
import shutil
import sys
from urllib.parse import quote

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402
import protocol_logins  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the zones examples for real")

c = st_client.Checker("Zones, run for real from Admin/API 2.0/bash/37.Zones")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "37.Zones")
SUFFIX = "%04x%04x" % (random.randint(0, 0xFFFF), random.randint(0, 0xFFFF))
ZONE = "example_zone_" + SUFFIX
UPPER = ZONE.upper()
SPACED = "example zone " + SUFFIX
FULL = "example_zfull_" + SUFFIX
BU = "example_zbu_" + SUFFIX
BU2 = "example_zbu2_" + SUFFIX
ACCOUNT = "example_zacct_" + SUFFIX
PASSWORD = harness.new_password()
HOST = config["st_server"]


def zp(name):
    return "zones/" + quote(name, safe="")


script = harness.bind_script(c, FOLDER, timeout=120, tail=400, arg_width=30)


def all_zones():
    response = admin.get("zones", params={"limit": 0})
    return sorted((response.json() or {}).get("result", []), key=lambda z: z["name"]) if response.status == 200 else None


def zone(name):
    response = admin.get(zp(name))
    return response.json() if response.status == 200 else None


def names():
    found = all_zones()
    return None if found is None else [z["name"] for z in found]


def settled(name, condition, seconds=15):
    return harness.settled(lambda: zone(name), condition, seconds) or {}


def without_description(z):
    return {k: v for k, v in (z or {}).items() if k != "description"}


# ---- logins: SFTP and HTTP are the core, FTP the legacy, additional part (the shared protocol_logins) ----
def logs_in(protocol, account):
    return logins.try_login(protocol, account) == "ok"


admin = harness.connect(config, c, mock="the bundled mock does not implement /zones or the protocol servers")
saved = all_zones()
if saved is None or any(z["name"].lower().startswith("example") for z in saved):
    c.check("no zone named example* exists yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())
ports = harness.ports(config, admin)
daemons = admin.get("daemons").json()
ENDUSER_PORT, FTP_PORT, SSH_PORT = ports.enduser, ports.ftp, ports.ssh
missing = []
if not SSH_PORT or daemons.get("sshStatus") != "Running":
    missing.append("the SSH daemon is not running (SFTP)")
if not shutil.which("sftp"):
    missing.append("there is no sftp client on this machine")
if missing:
    c.check("SFTP and HTTP can be exercised", False, "; ".join(missing))
    admin.logout()
    sys.exit(c.done())
private = [z for z in saved if z["name"] == "Private"]
c.check("set up: the server has the zone Private, saved with the rest to compare with at the end", len(private) == 1, [z["name"] for z in saved])
units = []
logins = protocol_logins.Logins(HOST, SSH_PORT, ENDUSER_PORT, FTP_PORT, PASSWORD)
account_stack = contextlib.ExitStack()

try:
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        # -- 01 ---------------------------------------------------------------------------
        c.info("--- 01 lists the zones")
        out = ""

        def listed():
            global out
            out = script("01.zones_GET.sh")
            return "Zones on the server: %d" % len(saved) in out
        c.check("01 counts the zones the API counts", harness.wait_until(listed, 20), out[:200])
        p = private[0]
        c.check("01 prints a line per zone: name, default, edges, description",
                "  Private  default %s  edges %d  %s" % (str(p["isDefault"]).lower(), len(p["edges"]), p["description"] or "-") in out, out[-400:])
        out = script("01.zones_GET.sh", ["Private"])
        c.check("01 a name lists that zone only", out.count("  default ") == 1 and "  Private  default" in out, out[-300:])
        out = script("01.zones_GET.sh", ["private"])
        c.check("01 the name is case sensitive: `private` lists nothing", "  default " not in out, out[-300:])
        out = script("01.zones_GET.sh", ["Priv*"])
        c.check("01 and takes no wildcard", "  default " not in out, out[-300:])

        # -- 02 ---------------------------------------------------------------------------
        c.info("--- 02 creates zones")
        out = script("02.zones_POST.sh", [ZONE])
        c.check("02 says HTTP 201 and where it is", "HTTP 201" in out and "/zones/%s" % ZONE in out, out[-300:])
        z = settled(ZONE, lambda z: True)
        c.check("02 the zone is as asked: the default description, no edge, not the default, nothing else set",
                (z.get("description"), z.get("edges"), z.get("isDefault"), z.get("publicURLPrefix"), z.get("ssoSpEntityId"), z.get("isDnsResolutionEnabled"))
                == ("Created by the examples", [], False, None, None, False), z)
        out = script("02.zones_POST.sh", [ZONE], expect_rc=1)
        c.check("02 a duplicate is the server's 400 'not unique' (the reference lists 409)", "HTTP 400" in out and "The zone name is not unique." in out, out[-300:])
        script("02.zones_POST.sh", [UPPER])
        c.check("02 names are case sensitive: %s is another zone" % UPPER, settled(UPPER, lambda z: True).get("name") == UPPER and zone(ZONE) is not None)
        script("07.zones_name_DELETE.sh", [UPPER])
        c.check("07 deleted that one only: %s is still there" % ZONE, harness.wait_until(lambda: zone(UPPER) is None) and zone(ZONE) is not None)
        out = script("02.zones_POST.sh", [SPACED, "d with a \"quote\"", "e1", "edge.example.invalid", "8022"])
        c.check("02 a name with a space: the Location holds it URL-encoded", "HTTP 201" in out and "/zones/" + quote(SPACED, safe="") in out, out[-300:])
        z = settled(SPACED, lambda z: True)
        edge = (z.get("edges") or [{}])[0]
        c.check("02 the edge: title, deployment site Prod, no proxy, one address, one SSH protocol on 8022 left disabled",
                (edge.get("title"), edge.get("deploymentSite"), edge.get("enabledProxy"), [a["ipAddress"] for a in edge.get("ipAddresses", [])],
                 [(x["streamingProtocol"], x["port"], x["isEnabled"]) for x in edge.get("protocols", [])]) == ("e1", "Prod", False, ["edge.example.invalid"], [("SSH", 8022, False)])
                and edge.get("edgeId"), z)
        c.check("02 the description keeps its quote", z.get("description") == 'd with a "quote"', z.get("description"))
        before = names()
        for bad in (["a/b"], ["a;b"], ["a'b"], ["x" * 256], [ZONE + "x", "d", "", "edge.example.invalid"], [ZONE + "x", "d", "t", "", "80"], [ZONE + "x", "d", "t", "", "abc"],
                    [ZONE + "x", "d", "a/b"], [ZONE + "x", "x" * 256]):
            script("02.zones_POST.sh", bad, expect_rc=2)
        c.check("02 the refusals sent nothing: the list of zones is as it was", names() == before, names())
        raw = admin.post("zones", {})
        c.check("raw POST: a body without a name is 400 'name must not be null'", raw.status == 400 and "name must not be null" in raw.text, raw.text[:200])
        raw = admin.post("zones", {"name": ZONE + "y", "bogus": 1})
        c.check("raw POST: an unknown field is 400 'Unsupported parameter - bogus'", raw.status == 400 and "Unsupported parameter - bogus" in raw.text, raw.text[:200])
        raw = admin.post("zones", {"name": ZONE + "y", "edges": [{"notes": "no title"}]})
        c.check("raw POST: an edge without a title is 400", raw.status == 400 and "title must not be null" in raw.text, raw.text[:200])
        raw = admin.post("zones", {"name": ZONE + "y", "edges": [{"title": "e", "protocols": [{"streamingProtocol": "HTTP", "port": 80}]}]})
        c.check("raw POST: a protocol port below 1024 is 400", raw.status == 400 and "from 1024 to 65535" in raw.text, raw.text[:200])
        raw = admin.post("zones", {"name": ZONE + "y", "edges": [{"title": "e", "protocols": [{"streamingProtocol": "HTTP", "port": 8443, "sslAlias": "example_nosuch_alias"}]}]})
        c.check("raw POST: a protocol sslAlias that is no certificate is 400 'Error creating zone'", raw.status == 400 and "Error creating zone" in raw.text, raw.text[:200])
        c.check("raw POST: none of those created a zone", zone(ZONE + "y") is None)

        # -- 03 ---------------------------------------------------------------------------
        c.info("--- 03 and 04 check and read one")
        out = script("03.zones_name_HEAD.sh", [ZONE])
        c.check("03 says it exists", "The zone %s exists." % ZONE in out, out[-200:])
        out = script("03.zones_name_HEAD.sh", [SPACED])
        c.check("03 finds the name with a space", "exists." in out, out[-200:])
        script("03.zones_name_HEAD.sh", ["example_nosuch"], expect_rc=1)
        script("03.zones_name_HEAD.sh", ["private"], expect_rc=1)
        c.check("HEAD of a missing zone is 404 with no body", admin.head(zp("example_nosuch")).status == 404)
        gone = admin.get(zp("example_nosuch"))
        c.check("GET of a missing zone is a JSON 404 'Zone with name X not found.'", gone.status == 404 and "not found" in gone.text, gone.text[:200])

        out = script("04.zones_name_GET.sh", [SPACED])
        c.check("04 prints the summary: the edge with its protocol, no proxy, one address", all(t in out for t in (
            "  %s, default false, 1 edge(s)" % SPACED, "  edge e1: 1 protocol(s), 0 prox(ies), 1 address(es)")), out[-500:])
        c.check("04 no business unit names it yet", "  business units that name it: none" in out, out[-200:])
        script("04.zones_name_GET.sh", ["example_nosuch"], expect_rc=1)
        out = script("04.zones_name_GET.sh", ["Private"])
        c.check("04 reads the lab's own zone (read only)", '"name" : "Private"' in out and "  Private, default" in out, out[-300:])

        # -- 05 and 06, on a zone with everything set ------------------------------------------
        c.info("--- 05 and 06 change the description and nothing else")
        full = {"name": FULL, "description": "d", "publicURLPrefix": "https://example.invalid/x", "ssoSpEntityId": "eid", "isDnsResolutionEnabled": True,
                "edges": [{"title": "e1", "notes": "n", "enabledProxy": True,
                           "protocols": [{"streamingProtocol": "HTTP", "port": 8443, "isEnabled": True}],
                           "proxies": [{"proxyProtocol": "SOCKS_PROXY", "port": 1081, "isEnabled": True, "username": "u", "isUsePassword": True, "password": "pw"}],
                           "ipAddresses": [{"ipAddress": "edge.example.invalid"}]}]}
        c.check("set up: a zone with an edge, a protocol, a proxy with a password, an address", admin.post("zones", full).status == 201)
        was = settled(FULL, lambda z: True)
        c.check("the proxy's password is never read back, its flag is", was["edges"][0]["proxies"][0]["password"] is None and was["edges"][0]["proxies"][0]["isUsePassword"] is True, was)
        out = script("05.zones_name_PUT.sh", [FULL, "put text"])
        c.check("05 says the description before and HTTP 204", "The description of %s is now: d" % FULL in out and "HTTP 204" in out, out[-300:])
        now = settled(FULL, lambda z: z.get("description") == "put text")
        c.check("05 changed the description", now.get("description") == "put text", now)
        c.check("05 and nothing else: the whole zone, the edge id and the proxy's flag included, is as it was", without_description(now) == without_description(was),
                (without_description(now), without_description(was)))
        out = script("06.zones_name_PATCH.sh", [FULL, "patch text"])
        c.check("06 says the description before and HTTP 204", "The description of %s is now: put text" % FULL in out and "HTTP 204" in out, out[-300:])
        now = settled(FULL, lambda z: z.get("description") == "patch text")
        c.check("06 changed the description and nothing else", now.get("description") == "patch text" and without_description(now) == without_description(was), now)
        script("05.zones_name_PUT.sh", ["example_nosuch"], expect_rc=1)
        script("05.zones_name_PUT.sh", [], expect_rc=2)
        script("05.zones_name_PUT.sh", [FULL, "x" * 256], expect_rc=2)
        script("06.zones_name_PATCH.sh", [], expect_rc=2)
        script("06.zones_name_PATCH.sh", [FULL, "x" * 256], expect_rc=2)
        out = script("06.zones_name_PATCH.sh", ["example_nosuch"], expect_rc=1)
        c.check("06 an unknown zone is the server's 404", "HTTP 404" in out, out[-200:])
        c.check("none of those changed the zone", zone(FULL).get("description") == "patch text")

        # the raw API: a PUT replaces, a PATCH does not
        put = admin.put(zp(FULL), {"name": FULL, "description": "only"})
        z = settled(FULL, lambda z: z.get("description") == "only")
        c.check("raw PUT of name and description: 204, and it RESETS publicURLPrefix, ssoSpEntityId and isDnsResolutionEnabled",
                put.status == 204 and (z.get("publicURLPrefix"), z.get("ssoSpEntityId"), z.get("isDnsResolutionEnabled")) == (None, None, False), (put.status, z))
        c.check("raw PUT with no `edges` key KEEPS the edges", len(z.get("edges") or []) == 1 and z["edges"][0]["notes"] == "n", z.get("edges"))
        put = admin.put(zp(FULL), {"name": FULL, "edges": [{"title": "e1"}]})
        z = settled(FULL, lambda z: z.get("description") is None)
        c.check("raw PUT of an edge with only a title: the edge loses its notes, protocols and enabledProxy",
                put.status == 204 and (z["edges"][0]["notes"], z["edges"][0]["protocols"], z["edges"][0]["enabledProxy"]) == (None, [], False), z.get("edges"))
        put = admin.put(zp(FULL), {"name": FULL, "edges": []})
        c.check("raw PUT with `edges: []` removes every edge", put.status == 204 and settled(FULL, lambda z: z["edges"] == []).get("edges") == [])
        raw = admin.put(zp(FULL), {"name": FULL + "_other"})
        c.check("raw PUT with another name is 400, not a rename", raw.status == 400 and "does not match" in raw.text and zone(FULL) is not None and zone(FULL + "_other") is None, raw.text[:200])
        raw = admin.put(zp(FULL), {"description": "no name"})
        c.check("raw PUT without a name is 400 'name must not be null'", raw.status == 400 and "name must not be null" in raw.text, raw.text[:200])
        c.check("raw PUT of an unknown zone is a JSON 404", admin.put(zp("example_nosuch"), {"name": "example_nosuch"}).status == 404)

        for body, label in (([{"op": "replace", "path": "/name", "value": FULL + "_x"}], "/name"), ([{"op": "replace", "path": "/nope", "value": "x"}], "a path that does not exist")):
            raw = admin.patch(zp(FULL), body)
            c.check("raw PATCH of %s is 400" % label, raw.status == 400, raw.text[:200])
        c.check("raw PATCH: an empty patch is 204", admin.patch(zp(FULL), []).status == 204)
        c.check("set up: one edge again", admin.put(zp(FULL), {"name": FULL, "edges": [{"title": "e1", "notes": "n"}]}).status == 204
                and len(settled(FULL, lambda z: len(z["edges"]) == 1)["edges"]) == 1)
        raw = admin.patch(zp(FULL), [{"op": "add", "path": "/edges/-", "value": {"title": "e2", "ipAddresses": [{"ipAddress": "e2.example.invalid"}]}}])
        z = settled(FULL, lambda z: len(z["edges"]) == 2)
        c.check("raw PATCH: add an edge at `/edges/-`", raw.status == 204 and [e["title"] for e in z["edges"]] == ["e1", "e2"], z.get("edges"))
        raw = admin.patch(zp(FULL), [{"op": "replace", "path": "/edges/1/notes", "value": "second"}, {"op": "replace", "path": "/publicURLPrefix", "value": "https://example.invalid/p"}])
        z = settled(FULL, lambda z: z.get("publicURLPrefix") == "https://example.invalid/p")
        c.check("raw PATCH: replace an edge's notes and the publicURLPrefix, in one patch", raw.status == 204 and z["edges"][1]["notes"] == "second", z)
        raw = admin.patch(zp(FULL), [{"op": "remove", "path": "/edges/1"}])
        c.check("raw PATCH: remove an edge by its position", raw.status == 204 and [e["title"] for e in settled(FULL, lambda z: len(z["edges"]) == 1)["edges"]] == ["e1"])
        raw = admin.patch(zp(FULL), [{"op": "replace", "path": "/description", "value": "x" * 256}])
        c.check("raw PATCH: a description of 256 characters is 400", raw.status == 400 and "255" in raw.text, raw.text[:200])

        # the default zone: there is only one, whichever way it is set
        c.info("--- the default zone")
        raw = admin.patch(zp(FULL), [{"op": "replace", "path": "/isDefault", "value": True}])
        c.check("raw PATCH /isDefault true makes it the default", raw.status == 204 and settled(FULL, lambda z: z["isDefault"]).get("isDefault") is True)
        out = script("01.zones_GET.sh")
        c.check("01 lists the default zone in its last section", "The default zone:\n  %s  default true" % FULL in out, out[-400:])
        put = admin.put(zp(ZONE), {"name": ZONE, "isDefault": True})
        c.check("raw PUT of another zone with isDefault true makes THAT the only default",
                put.status == 204 and harness.wait_until(lambda: [z["name"] for z in (all_zones() or []) if z["isDefault"]] == [ZONE]), [z["name"] for z in (all_zones() or []) if z["isDefault"]])
        put = admin.put(zp(ZONE), {"name": ZONE})
        c.check("raw PUT with no isDefault turns it off: there is no default again",
                put.status == 204 and harness.wait_until(lambda: [z["name"] for z in (all_zones() or []) if z["isDefault"]] == []))
        raw = admin.patch(zp(FULL), [{"op": "replace", "path": "/isDefault", "value": True}])
        made = admin.post("businessUnits", {"name": BU2, "baseFolder": "/" + BU2})
        if made.status == 201:
            units.append(BU2)
        c.check("raw PATCH /isDefault true on %s, and a business unit created without a dmz" % FULL, raw.status == 204 and made.status == 201, (raw.status, made.text[:200]))
        bu2 = admin.get("businessUnits/" + quote(BU2, safe=""))
        c.check("... (read back) the unit created while %s was the default has dmz null" % FULL, bu2.status == 200 and bu2.json().get("dmz") is None, bu2.text[:200])
        admin.delete("businessUnits/" + quote(BU2, safe=""))
        units.remove(BU2) if BU2 in units else None
        admin.patch(zp(FULL), [{"op": "replace", "path": "/isDefault", "value": False}])
        c.check("the default is off again", harness.wait_until(lambda: [z["name"] for z in (all_zones() or []) if z["isDefault"]] == []))

        # -- the effect: a business unit names a zone ------------------------------------------
        c.info("--- what naming a zone changes: a business unit whose dmz is a zone with an edge")
        raw = admin.post("businessUnits", {"name": BU, "baseFolder": "/" + BU, "dmz": "example_nosuch"})
        c.check("a business unit that names a zone that does not exist is 400 'No such DMZ zone'", raw.status == 400 and "No such DMZ zone" in raw.text, raw.text[:200])
        c.check("set up: a business unit naming the zone %s" % SPACED, admin.post("businessUnits", {"name": BU, "baseFolder": "/" + BU, "dmz": SPACED}).status == 201)
        units.append(BU)
        account_stack.enter_context(harness.throwaway_account(
            admin, c, config, name=ACCOUNT, password=PASSWORD, home="/%s/%s" % (BU, ACCOUNT), extra={"businessUnit": BU},
            label="set up: an account in that unit"))
        out = ""

        def names_it():
            global out
            out = script("04.zones_name_GET.sh", [SPACED])
            return "  business units that name it: %s" % BU in out
        c.check("04 lists the unit that names the zone", harness.wait_until(names_it, 20), out[-300:])
        out = script("04.zones_name_GET.sh", [FULL])
        c.check("04 and no unit for a zone that none names", "  business units that name it: none" in out, out[-200:])
        c.check("the unit reads back its zone in dmz", admin.get("businessUnits/" + quote(BU, safe="")).json().get("dmz") == SPACED)
        c.check("CORE: an SFTP login of the account in that unit works, exactly as before (the edge changes nothing on a standalone server)",
                harness.wait_until(lambda: logs_in("SFTP", ACCOUNT), 30))
        c.check("CORE: an HTTP (EndUser API) login works too", harness.wait_until(lambda: logs_in("HTTP", ACCOUNT), 30))
        if FTP_PORT and daemons.get("ftpStatus") == "Running":
            c.info("--- FTP: the legacy protocol, as an additional part")
            c.check("additional, legacy: an FTP login works too", harness.wait_until(lambda: logs_in("FTP", ACCOUNT), 30))
        out = script("07.zones_name_DELETE.sh", [SPACED], expect_rc=1)
        c.check("07 a zone that a unit names is refused (the server answers 500) and says why", "HTTP 500" in out and "Database error deleting DMZ zone" in out, out[-300:])
        c.check("07 the zone is still there, and so is the unit's dmz", zone(SPACED) is not None and admin.get("businessUnits/" + quote(BU, safe="")).json().get("dmz") == SPACED)
        c.check("the unit's login still works after the refusal", logs_in("SFTP", ACCOUNT) and logs_in("HTTP", ACCOUNT))
        account_stack.close()   # the unit's account is deleted first: the unit and then the zone cannot go while it is there
        admin.delete("businessUnits/" + quote(BU, safe=""))
        units.remove(BU)
        out = script("07.zones_name_DELETE.sh", [SPACED])
        c.check("07 once the unit is gone the zone is deleted: HTTP 204", "HTTP 204" in out and harness.wait_until(lambda: zone(SPACED) is None), out[-300:])

        # -- 07 ---------------------------------------------------------------------------
        c.info("--- 07 deletes")
        out = script("07.zones_name_DELETE.sh", [ZONE])
        c.check("07 deletes a zone: HTTP 204", "HTTP 204" in out and harness.wait_until(lambda: zone(ZONE) is None), out[-200:])
        out = script("07.zones_name_DELETE.sh", [ZONE], expect_rc=1)
        c.check("07 a second delete is 404 'not found'", "HTTP 404" in out and "not found" in out, out[-200:])
        out = script("07.zones_name_DELETE.sh", [FULL])
        c.check("07 deletes the zone with an edge and a proxy", "HTTP 204" in out and harness.wait_until(lambda: zone(FULL) is None), out[-200:])
        script("07.zones_name_DELETE.sh", [], expect_rc=2)
        c.check("the refusals and the 404s deleted nothing else: Private is still there", zone("Private") is not None)
finally:
    logins.cleanup()
    account_stack.close()
    for unit in units:
        admin.delete("businessUnits/" + quote(unit, safe=""))
    for name in (ZONE, UPPER, SPACED, FULL, ZONE + "x", ZONE + "y", FULL + "_other", FULL + "_x"):
        if zone(name) is not None:
            admin.delete(zp(name))
    after = all_zones()
    c.check("nothing is left behind and the whole list of zones, Private included, is exactly what it was",
            harness.wait_until(lambda: all_zones() == saved), json.dumps([z["name"] for z in (after or [])]))
    admin.logout()

sys.exit(c.done())
