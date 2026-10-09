#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 35.TransferProfiles examples
against throwaway PeSIT accounts, reads each effect back through the API, and
shows what a profile does to a real PeSIT pull on the lab's own PeSIT server.

  - A transfer profile belongs to an account that has a PeSIT site: 02 on an
    account with none is refused (exit 1), and on one that does not exist too.
Two levels, as in check 59: CORE uses the profile's advancedSettings (what 02 creates by default,
and what 05 and 06 change by default), ADDITIONAL uses the plain fields (02 with the word basic, 05
with a - for the line ending, 06 with the side basic). What the settings do to a file's bytes is
check 59's job; this check is about the examples and the API around them.

  - 02 creates a profile (the id is in Location), with advancedSettings of the type asked for
    (binary, ascii, ebcdic) or without them (basic); a second of the same name is
    refused, and a name in other capitals is a different profile. 03, 04, 05, 06
    and 07 act on the exact name only, though the name filter ignores case.
  - 05 sends the whole profile back with the receiving line ending changed: nothing else moves;
    with a - it changes the send mapping (a plain field) instead. A profile with a binary
    receiving side has no line ending: the example sends nothing. A raw PUT of a fragment (with
    the id) resets what it leaves out.
  - 06 changes the record length of the receiving side, the sending side or the plain field,
    and nothing else.
  - 01 lists them, and the default ones; an account has at most one default.
  - 07 deletes one profile and no other; a second delete finds nothing (exit 1).
  - What a profile does: the receiver pulls a file from the sender over PeSIT.
    The profile the pull names (transferProfile) decides what the received file
    is called; a pull that names none uses the account's default profile. Three
    pulls (two advanced, one with the plain fields), so three (small) sets of transfer log entries that cannot be removed.

Names of the two PeSIT accounts are short and alphanumeric (they are PeSIT
partner identifiers), made new on every run together with a new user id, because
the home folder of a deleted account stays on disk with its first owner.

Needs --write and st_allow_writes="yes". Refuses to start when a profile whose
name starts with example_ exists. Removes the profiles, sites and accounts in a
finally block (the received and sent files first) and checks nothing is left.
"""
import contextlib
import os
import random
import sys
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the transfer profiles examples for real")

c = st_client.Checker("Transfer profiles, run for real from Admin/API 2.0/bash/35.TransferProfiles")


def core(text):
    return "core (advancedSettings): " + text


def extra(text):
    return "additional (plain fields): " + text

BASH = runner.path("Admin", "API 2.0", "bash")
FOLDER = os.path.join(BASH, "35.TransferProfiles")

N = random.randint(1000, 9999)
SENDER, RECEIVER, PLAIN = "TPS%d" % N, "TPR%d" % N, "TPN%d" % N
PASSWORD = harness.new_password()
HOST = config["st_server"]
PESIT_HOST = config.get("st_pesit_host") or config["st_server"]
ENDUSER_PORT = harness.ports(config).enduser
EXAMPLE, UPPER, SACRIFICE = "example_profile", "EXAMPLE_PROFILE", "example_sacrifice"
SEND_PROFILE, FIXED_PROFILE, DEFAULT_PROFILE, BASIC_PROFILE = "PRFS", "PRFB", "PRFD", "PRFX"
ASCII_NAME, BASIC_NAME = "example_ascii", "example_basic"
BASIC_LANDED = "landed_by_prfx_%d.txt" % N
BINARY_ADV = {"enabled": True, "callerTranscoding": {"type": "binary"}, "receiverTranscoding": {"type": "binary"}}
SENT_FILE = "tp_probe_%d.txt" % N
FIXED_NAME = "landed_by_prfb_%d.txt" % N
PESIT_SITE_DEFAULTS = {"dmz": "none", "pesitId": "", "ptcpConnections": 1, "socketSendReceiveBuffersize": 65536,
                       "receiveMessage": "", "sendMessage": "", "useServerPasswordExpr": False,
                       "usePartnerPasswordExpr": False, "usePreconnectionServerPasswordExpr": False,
                       "usePreconnectionPartnerPasswordExpr": False}


# The list of profiles is not always complete: when the lookup found none for a profile that is known to exist
# (retry=True), the example is run again, up to five times
script = harness.bind_script(c, FOLDER, timeout=120, tail=400, retry_text="Found 0 transfer profiles named")


def profiles(account):
    response = admin.get("transferProfiles", params={"account": account})
    return (response.json() or {}).get("result", []) if response.status == 200 else []


def find(account, name):
    found = [p for p in profiles(account) if p["name"] == name]
    return found[0] if len(found) == 1 else None


def settled(account, name, condition, seconds=30):
    """Read the profile until condition(profile) is true, and return it (or the last one read)."""
    return harness.settled(lambda: find(account, name), condition, seconds) or {}


def without(profile, *keys):
    return {k: v for k, v in profile.items() if k not in keys}


def pesit_site(owner, partner):
    response = admin.post("sites", {"type": "pesit", "protocol": "pesit", "name": partner, "account": owner, "host": PESIT_HOST,
                                    "port": PESIT_PORT, "transferType": "unspecified", "storeAndForwardMode": "PRESERVE",
                                    **PESIT_SITE_DEFAULTS})
    c.check("set up: %s has a PeSIT site %s, pointing at this server" % (owner, partner), response.status == 201, response.text[:200])


def pull(profile=None):
    """Start a pull by RECEIVER from SENDER into /landing; wait for it; return its operationIndex."""
    body = {"accountName": RECEIVER, "site": SENDER, "destinationDirectory": "/landing", "awaitResult": False}
    if profile:
        body["transferProfile"] = profile
    response = admin.post("transfers/operations", body, params={"operation": "pull"})
    c.check("the pull (%s) is accepted" % (profile or "no profile named"), response.status == 202, response.text[:200])
    index = urllib.parse.parse_qs(urllib.parse.urlparse((response.json() or {}).get("link", "")).query).get("operationIndex", [""])[0]

    def done():
        rows = admin.get("logs/transfers", params={"account": RECEIVER, "sortByStartTime": "descending", "limit": 20}).json().get("result", [])
        mine = [r for r in rows if str(r.get("operationIndex")) == index]
        return bool(mine) and mine[0]["status"] in ("Processed", "Failed")
    harness.wait_until(done, 60, 2)
    rows = admin.get("logs/transfers", params={"account": RECEIVER, "sortByStartTime": "descending", "limit": 20}).json().get("result", [])
    return index, [r for r in rows if str(r.get("operationIndex")) == index]


admin = harness.connect(config, c, mock="the bundled mock does not implement /transferProfiles, PeSIT or /logs/transfers")
if (admin.get("transferProfiles", params={"name": "example_*"}).json() or {}).get("result"):
    c.check("no transfer profile named example_* exists yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

PESIT_PORT = harness.ports(config, admin).pesit
before = (admin.get("transferProfiles", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount")
accounts = []
user_accounts = contextlib.ExitStack()
eu_sender = eu_receiver = None
landed = []
try:
    for name in (SENDER, RECEIVER, PLAIN):
        user_accounts.enter_context(harness.throwaway_account(admin, c, config, name=name, password=PASSWORD,
                                                             extra={"transfersWebServiceAllowed": True}))
        accounts.append(name)
    pesit_site(RECEIVER, SENDER)
    pesit_site(SENDER, RECEIVER)

    with runner.real_credentials(BASH, config):
        # -- 02: create ---------------------------------------------------------------
        c.info("--- 02 creates, and what the server refuses")
        out = script("02.transferProfiles_POST.sh", [RECEIVER, EXAMPLE, "/a.txt", "in_${pesit.fileName}"])
        made = settled(RECEIVER, EXAMPLE, lambda p: True)
        c.check("02 created it: the address it printed ends with the profile's id", made.get("id") and made["id"] in out, out[-200:])
        c.check(core("02: the mappings are stored with a / in front, the label is DONT_SEND, the rest are defaults"),
                (made.get("sendMapping"), made.get("receiveMapping"), made.get("fileLabelOption"), made.get("default"),
                 made.get("transferMode"), made.get("recordFormat"), made.get("recordLength"))
                == ("/a.txt", "/in_${pesit.fileName}", "DONT_SEND", False, "BINARY", "Variable", 2048), made)
        adv = made.get("advancedSettings") or {}
        c.check(core("02: advancedSettings are on, binary on both sides, the read-only parts filled in by the server"),
                adv.get("enabled") is True and (adv.get("callerTranscoding") or {}) == {"type": "binary", "localDataCode": "BINARY", "networkDataCode": "BINARY",
                                                                                         "outputRecordFormat": "VARIABLE", "outputRecordLength": 2048}
                and (adv.get("receiverTranscoding") or {}) == {"type": "binary", "localDataCode": "BINARY"}, adv)
        out = script("02.transferProfiles_POST.sh", [RECEIVER, ASCII_NAME, "/c.txt", "", "ascii"])
        ascii_made = settled(RECEIVER, ASCII_NAME, lambda p: True)
        adv = ascii_made.get("advancedSettings") or {}
        c.check(core("02 ascii: both sides are ascii, with the defaults the server fills in (variable records of 2048, space padding, default line ending)"),
                adv.get("enabled") is True and adv.get("callerTranscoding") == {"type": "ascii", "localDataCode": "ASCII", "networkDataCode": "ASCII", "outputRecordFormat": "VARIABLE",
                                                                                "outputRecordLength": 2048, "paddingCharacter": "\\u0020"}
                and adv.get("receiverTranscoding") == {"type": "ascii", "localDataCode": "ASCII", "outputRecordFormat": "VARIABLE", "outputRecordLength": 2048,
                                                       "paddingCharacter": "\\u0020", "lineEndingFormat": "DEFAULT"}, adv)
        script("02.transferProfiles_POST.sh", [RECEIVER, "example_ebcdic", "/d.txt", "", "ebcdic"])
        ebcdic_adv = (settled(RECEIVER, "example_ebcdic", lambda p: True).get("advancedSettings") or {})
        c.check(core("02 ebcdic: the padding character defaults to \\u0040, and the data is EBCDIC"),
                (ebcdic_adv.get("callerTranscoding") or {}).get("networkDataCode") == "EBCDIC" and (ebcdic_adv.get("receiverTranscoding") or {}).get("paddingCharacter") == "\\u0040", ebcdic_adv)
        out = script("02.transferProfiles_POST.sh", [RECEIVER, BASIC_NAME, "/e.txt", "", "basic"])
        basic_made = settled(RECEIVER, BASIC_NAME, lambda p: True)
        c.check(extra("02 basic: no advancedSettings were sent, so the server stores them off, and the plain fields are in force"),
                (basic_made.get("advancedSettings") or {}).get("enabled") is False and basic_made.get("transferMode") == "BINARY", basic_made.get("advancedSettings"))
        script("02.transferProfiles_POST.sh", [RECEIVER, "example_bad", "/a.txt", "", "Binary"], expect_rc=2)
        raw = admin.post("transferProfiles", {"name": "example_bad", "account": RECEIVER, "sendMapping": "/a", "fileLabelOption": "DONT_SEND",
                                              "advancedSettings": {"enabled": True, "callerTranscoding": {"type": "Binary"}}})
        c.check(core("an unknown advancedSettings type (even in other capitals) is refused by the server (400)"), raw.status == 400, raw.text[:200])
        out = script("02.transferProfiles_POST.sh", [RECEIVER, EXAMPLE, "/a.txt"], expect_rc=1)
        c.check("02: a second profile of that name on the account is refused", "cannot have the same account and name" in out, out[-300:])
        script("02.transferProfiles_POST.sh", [RECEIVER, UPPER, "/b.txt"])
        c.check("02: the same name in other capitals is another profile", find(RECEIVER, UPPER) is not None and find(RECEIVER, EXAMPLE) is not None,
                [p["name"] for p in profiles(RECEIVER)])
        out = script("02.transferProfiles_POST.sh", [PLAIN, EXAMPLE, "/a.txt"], expect_rc=1)
        c.check("02: an account with no PeSIT site is refused", "does not contain any PeSIT transfer sites" in out, out[-300:])
        out = script("02.transferProfiles_POST.sh", ["TPNOSUCH%d" % N, EXAMPLE, "/a.txt"], expect_rc=1)
        c.check("02: an account that does not exist is refused", "Cannot find account" in out, out[-300:])
        script("02.transferProfiles_POST.sh", [RECEIVER, "example_bad", "/a.txt", "a*"], expect_rc=2)
        c.check("02: a receive mapping with a * sent nothing", find(RECEIVER, "example_bad") is None)
        c.check("02: neither did a TRANSCODING that is not one of the four", find(RECEIVER, "example_bad") is None)
        raw = admin.post("transferProfiles", {"name": "example_bad", "account": RECEIVER, "receiveMapping": "a*", "fileLabelOption": "DONT_SEND"})
        c.check("   and the server refuses it too (400)", raw.status == 400 and "may not contain" in raw.text, raw.text[:200])
        raw = admin.post("transferProfiles", {"name": "example_bad", "account": RECEIVER, "fileLabelOption": "DONT_SEND"})
        c.check("   as it does a profile with neither mapping (400)", raw.status == 400 and "At least one" in raw.text, raw.text[:200])
        raw = admin.post("transferProfiles", {"name": "example_bad", "account": RECEIVER, "sendMapping": "/a"})
        c.check("   or one with no fileLabelOption (400)", raw.status == 400 and "fileLabelOption" in raw.text, raw.text[:200])
        c.check("   and none of those was created", find(RECEIVER, "example_bad") is None)

        # -- 03 / 04: HEAD and GET, the exact name -------------------------------------
        c.info("--- 03 and 04 pick the exact name out of a filter that ignores case")
        raw = [p["name"] for p in (admin.get("transferProfiles", params={"account": RECEIVER, "name": EXAMPLE}).json() or {}).get("result", [])]
        c.check("the name filter returns both capitalisations", sorted(raw) == sorted([EXAMPLE, UPPER]), raw)
        out = script("03.transferProfiles_id_HEAD.sh", [RECEIVER, EXAMPLE])
        c.check("03 says it exists, with the id of the lower case one", "exists, id %s" % made["id"] in out, out[-200:])
        script("03.transferProfiles_id_HEAD.sh", [RECEIVER, "example_nope"], expect_rc=1, retry=False)
        out = script("04.transferProfiles_id_GET.sh", [RECEIVER, EXAMPLE])
        c.check(core("04 prints the advanced settings: sending and receiving types"),
                "  advanced:    true" in out and "  sending:     binary, VARIABLE records of 2048" in out and "  receiving:   binary, line ending -" in out, out[-400:])
        c.check("04 prints the profile's mappings, label and mode",
                "  send:        /a.txt" in out and "  receive:     /in_${pesit.fileName}" in out and "  file label:  DONT_SEND" in out
                and "  mode:        BINARY, Variable records of 2048" in out, out[-400:])
        c.check("04 reads only some fields too", '"sendMapping" : "/a.txt"' in out and '"name" : "example_profile"' in out, out[-300:])
        one = admin.get("transferProfiles/" + made["id"])
        c.check("GET of one is the same object the list gave", one.status == 200 and without(one.json(), "metadata") == without(made, "metadata"), one.text[:200])
        c.check("HEAD of the id is 200, of an id that does not exist 404, of a bad one 404",
                admin.head("transferProfiles/" + made["id"]).status == 200
                and admin.head("transferProfiles/8a050087a0e7255001a11acefab14999").status == 404 and admin.head("transferProfiles/zzz").status == 404)
        gone = admin.get("transferProfiles/zzz")
        c.check("GET of an id that is not there is a JSON 404", gone.status == 404 and "not found or not accessible" in gone.text, gone.text[:200])

        # -- 05: PUT --------------------------------------------------------------------
        c.info("--- 05 sends the whole profile back")
        rich = admin.post("transferProfiles", {"name": SACRIFICE, "account": RECEIVER, "sendMapping": "/s.txt", "receiveMapping": "s_${pesit.fileName}",
                                               "fileLabelOption": "SEND_FILENAME", "transferMode": "ASCII", "recordFormat": "Fixed", "recordLength": 80,
                                               "multiSelect": True, "sendingAcknowledgmentEnabled": True, "paddingStripEnabled": True,
                                               "additionalAttributes": {"userVars.example_k": "v"}})
        c.check("set up: a profile with every plain setting changed from its default", rich.status == 201, rich.text[:200])
        sacrifice = settled(RECEIVER, SACRIFICE, lambda p: True)
        before_put = settled(RECEIVER, EXAMPLE, lambda p: True)
        # core: the line ending of the receiving side
        before_ascii = settled(RECEIVER, ASCII_NAME, lambda p: True)
        out = script("05.transferProfiles_id_PUT.sh", [RECEIVER, ASCII_NAME])
        after = settled(RECEIVER, ASCII_NAME, lambda p: (p.get("advancedSettings") or {}).get("receiverTranscoding", {}).get("lineEndingFormat") == "WINDOWS")
        want = dict(before_ascii["advancedSettings"]["receiverTranscoding"], lineEndingFormat="WINDOWS")
        c.check(core("05: the receiving line ending is WINDOWS, and nothing else moved (the sending side, the plain fields, the id)"),
                after.get("advancedSettings", {}).get("receiverTranscoding") == want
                and without(after, "advancedSettings") == without(before_ascii, "advancedSettings")
                and after["advancedSettings"]["callerTranscoding"] == before_ascii["advancedSettings"]["callerTranscoding"], after)
        c.check(core("05 printed the line ending before and HTTP 204"), "The lineEndingFormat of %s is now DEFAULT." % ASCII_NAME in out and "HTTP 204" in out, out[-300:])
        script("05.transferProfiles_id_PUT.sh", [RECEIVER, ASCII_NAME, "UNIX", "/changed_ascii.txt"])
        after = settled(RECEIVER, ASCII_NAME, lambda p: p.get("sendMapping") == "/changed_ascii.txt")
        c.check(core("05 UNIX /changed_ascii.txt: both changed (the line ending and, a plain field, the send mapping)"),
                after.get("advancedSettings", {}).get("receiverTranscoding", {}).get("lineEndingFormat") == "UNIX" and after.get("sendMapping") == "/changed_ascii.txt", after)
        out = script("05.transferProfiles_id_PUT.sh", [RECEIVER, EXAMPLE, "WINDOWS"], expect_rc=1, retry=False)
        c.check(core("05: a profile with a binary receiving side has no line ending: the example says so and sends nothing"),
                "has no receiving line ending" in out and without(find(RECEIVER, EXAMPLE), "metadata") == without(before_put, "metadata"), out[-300:])
        raw = admin.put("transferProfiles/" + before_ascii["id"], dict(without(settled(RECEIVER, ASCII_NAME, lambda p: True), "metadata"), advancedSettings={
            "enabled": True, "callerTranscoding": {"type": "ascii"}, "receiverTranscoding": {"type": "binary", "lineEndingFormat": "WINDOWS"}}))
        again = settled(RECEIVER, ASCII_NAME, lambda p: (p.get("advancedSettings") or {}).get("receiverTranscoding", {}).get("type") == "binary")
        c.check(core("a raw PUT can change a side's type (204), and a line ending sent to a binary side is dropped"),
                raw.status == 204 and again["advancedSettings"]["receiverTranscoding"] == {"type": "binary", "localDataCode": "BINARY"}, (raw.status, again.get("advancedSettings")))
        # additional: the plain send mapping
        out = script("05.transferProfiles_id_PUT.sh", [RECEIVER, SACRIFICE, "-", "/changed.txt"])
        after = settled(RECEIVER, SACRIFICE, lambda p: p.get("sendMapping") == "/changed.txt")
        c.check(extra("05 - /changed.txt: the send mapping changed, and nothing else (every setting, the attribute and the id kept)"),
                after.get("sendMapping") == "/changed.txt" and without(after, "sendMapping") == without(sacrifice, "sendMapping"), after)
        c.check(extra("05 printed the value before"), "The sendMapping of %s is now /s.txt." % SACRIFICE in out and "HTTP 204" in out, out[-300:])
        out = script("05.transferProfiles_id_PUT.sh", [RECEIVER, SACRIFICE, "WINDOWS"], expect_rc=1, retry=False)
        c.check(extra("05: a profile with the advanced settings off has no line ending: nothing sent"), "has no receiving line ending" in out, out[-300:])
        c.check("05 did not touch the profile of the same name in other capitals",
                without(find(RECEIVER, EXAMPLE), "metadata") == without(before_put, "metadata"))
        script("05.transferProfiles_id_PUT.sh", [RECEIVER, SACRIFICE, "-", "/s.txt"])
        script("05.transferProfiles_id_PUT.sh", [RECEIVER], expect_rc=2)
        script("05.transferProfiles_id_PUT.sh", [RECEIVER, SACRIFICE, "-"], expect_rc=2)
        script("05.transferProfiles_id_PUT.sh", [RECEIVER, "example_nope", "UNIX"], expect_rc=1, retry=False)
        # the fragment that the Notes warn about, once, on the sacrificial profile
        no_id = admin.put("transferProfiles/" + sacrifice["id"], {"name": SACRIFICE, "account": RECEIVER, "sendMapping": "/s.txt", "fileLabelOption": "DONT_SEND"})
        c.check("a raw PUT with no id is 400 \"id to load is required\"", no_id.status == 400 and "id to load is required" in no_id.text, no_id.text[:200])
        frag = admin.put("transferProfiles/" + sacrifice["id"], {"id": sacrifice["id"], "name": SACRIFICE, "account": RECEIVER, "sendMapping": "/s.txt",
                                                                 "fileLabelOption": "DONT_SEND"})
        reset = settled(RECEIVER, SACRIFICE, lambda p: p.get("transferMode") == "BINARY")
        c.check("a raw PUT of a fragment (with the id) answers 204 and silently resets the rest",
                frag.status == 204 and (reset.get("transferMode"), reset.get("recordFormat"), reset.get("recordLength"), reset.get("multiSelect"),
                                         reset.get("sendingAcknowledgmentEnabled"), reset.get("paddingStripEnabled"), reset.get("additionalAttributes"),
                                         reset.get("receiveMapping")) == ("BINARY", "Variable", 2048, False, False, False, {}, ""), reset)
        same = admin.put("transferProfiles/" + before_put["id"], dict(without(before_put, "metadata"), account=PLAIN))
        c.check("an account in a PUT body is accepted and ignored", same.status == 204 and find(RECEIVER, EXAMPLE) is not None
                and find(PLAIN, EXAMPLE) is None, same.text[:200])
        clash = admin.put("transferProfiles/" + before_put["id"], dict(without(before_put, "metadata"), name=SACRIFICE))
        c.check("renaming to a name the account has is refused with a 403, not a 400", clash.status == 403, (clash.status, clash.text[:200]))
        unknown = admin.put("transferProfiles/8a050087a0e7255001a11acefab14999", without(before_put, "metadata"))
        c.check("a PUT to an id that is not there is a 404", unknown.status == 404, unknown.text[:200])

        # -- 06: PATCH ------------------------------------------------------------------
        c.info("--- 06 changes the record length")
        ascii_now = settled(RECEIVER, ASCII_NAME, lambda p: True)
        # make the ascii profile ascii on both sides again for the patches
        admin.put("transferProfiles/" + ascii_now["id"], dict(without(ascii_now, "metadata"), advancedSettings={
            "enabled": True, "callerTranscoding": {"type": "ascii"}, "receiverTranscoding": {"type": "ascii"}}))
        base = settled(RECEIVER, ASCII_NAME, lambda p: (p.get("advancedSettings") or {}).get("receiverTranscoding", {}).get("type") == "ascii")
        out = script("06.transferProfiles_id_PATCH.sh", [RECEIVER, ASCII_NAME, "512"])
        after = settled(RECEIVER, ASCII_NAME, lambda p: (p.get("advancedSettings") or {}).get("receiverTranscoding", {}).get("outputRecordLength") == 512)
        c.check(core("06: the receiving side's record length changed, and nothing else"),
                after["advancedSettings"]["receiverTranscoding"] == dict(base["advancedSettings"]["receiverTranscoding"], outputRecordLength=512)
                and after["advancedSettings"]["callerTranscoding"] == base["advancedSettings"]["callerTranscoding"] and after.get("recordLength") == base.get("recordLength"), after)
        c.check(core("06 printed the value before and the side"), "The record length of %s (receiver) is now 2048." % ASCII_NAME in out and "HTTP 204" in out, out[-300:])
        script("06.transferProfiles_id_PATCH.sh", [RECEIVER, ASCII_NAME, "64", "caller"])
        after = settled(RECEIVER, ASCII_NAME, lambda p: (p.get("advancedSettings") or {}).get("callerTranscoding", {}).get("outputRecordLength") == 64)
        c.check(core("06 caller: the sending side's record length changed, the receiving side's stayed 512"),
                after["advancedSettings"]["callerTranscoding"]["outputRecordLength"] == 64 and after["advancedSettings"]["receiverTranscoding"]["outputRecordLength"] == 512, after)
        out = script("06.transferProfiles_id_PATCH.sh", [RECEIVER, EXAMPLE, "100"], expect_rc=1, retry=False)
        c.check(core("06: a binary receiving side has no record length: nothing sent, nothing changed"),
                "has no record length for receiver" in out and without(find(RECEIVER, EXAMPLE), "metadata") == without(before_put, "metadata"), out[-300:])
        out = script("06.transferProfiles_id_PATCH.sh", [RECEIVER, UPPER, "100"], expect_rc=1, retry=False)
        out = script("06.transferProfiles_id_PATCH.sh", [RECEIVER, ASCII_NAME, "100", "sender"], expect_rc=2, retry=False)
        raw = admin.patch("transferProfiles/" + base["id"], [{"op": "replace", "path": "/advancedSettings/callerTranscoding/type", "value": "ebcdic"}])
        c.check(core("a side's type cannot be patched: 400, it is a discriminator"), raw.status == 400 and "discriminator" in raw.text, raw.text[:200])
        bin_raw = admin.patch("transferProfiles/" + before_put["id"], [{"op": "replace", "path": "/advancedSettings/callerTranscoding/outputRecordLength", "value": 300}])
        c.check(core("a patch of a field the side's type does not have (a binary sender's length) answers 204 and changes nothing"),
                bin_raw.status == 204 and without(settled(RECEIVER, EXAMPLE, lambda p: True), "metadata") == without(before_put, "metadata"), bin_raw.text[:200])
        zero = admin.patch("transferProfiles/" + base["id"], [{"op": "replace", "path": "/advancedSettings/receiverTranscoding/outputRecordLength", "value": 0}])
        c.check(core("the server refuses an advanced record length of 0 (400)"), zero.status == 400 and "outputRecordLength must be greater than or equal to 1" in zero.text, zero.text[:200])
        ending = admin.patch("transferProfiles/" + base["id"], [{"op": "replace", "path": "/advancedSettings/receiverTranscoding/lineEndingFormat", "value": "MAC"}])
        c.check(core("a line ending that is not DEFAULT, WINDOWS or UNIX is 400"), ending.status == 400 and "DEFAULT, WINDOWS, UNIX" in ending.text, ending.text[:200])
        base = settled(RECEIVER, UPPER, lambda p: True)
        out = script("06.transferProfiles_id_PATCH.sh", [RECEIVER, UPPER, "512", "basic"])
        after = settled(RECEIVER, UPPER, lambda p: p.get("recordLength") == 512)
        c.check(extra("06 basic: the plain record length changed, and nothing else"), after.get("recordLength") == 512
                and without(after, "recordLength") == without(base, "recordLength"), after)
        c.check(extra("06 printed the value before"), "The record length of %s (basic) is now 2048." % UPPER in out and "HTTP 204" in out, out[-300:])
        script("06.transferProfiles_id_PATCH.sh", [RECEIVER, UPPER, "0", "basic"], expect_rc=2)
        script("06.transferProfiles_id_PATCH.sh", [RECEIVER, UPPER, "32768", "basic"], expect_rc=2)
        script("06.transferProfiles_id_PATCH.sh", [RECEIVER, UPPER, "abc", "basic"], expect_rc=2)
        script("06.transferProfiles_id_PATCH.sh", [RECEIVER, UPPER, "32767", "basic"])
        c.check(extra("06: the largest length, 32767, is accepted"),
                settled(RECEIVER, UPPER, lambda p: p.get("recordLength") == 32767).get("recordLength") == 32767)
        out = script("06.transferProfiles_id_PATCH.sh", [RECEIVER, "example_nope", "10"], expect_rc=1, retry=False)
        refused = admin.patch("transferProfiles/" + base["id"], [{"op": "replace", "path": "/recordLength", "value": 0}])
        c.check("the server refuses a plain record length of 0 (400)", refused.status == 400 and "recordLength must be greater than or equal to 1" in refused.text, refused.text[:200])
        refused = admin.patch("transferProfiles/" + base["id"], [{"op": "replace", "path": "/nope", "value": 1}])
        c.check("a path that does not exist is 400 Missing field", refused.status == 400 and 'Missing field "nope"' in refused.text, refused.text[:200])
        refused = admin.patch("transferProfiles/" + base["id"], [{"op": "replace", "path": "/receiveMapping", "value": "a?"}])
        c.check("a receive mapping with a ? is 400 in a patch too", refused.status == 400 and "may not contain" in refused.text, refused.text[:200])
        ok = admin.patch("transferProfiles/" + base["id"], [{"op": "add", "path": "/additionalAttributes/userVars.example_k", "value": "v"}])
        c.check("an additional attribute is added by a patch (204)",
                ok.status == 204 and settled(RECEIVER, UPPER, lambda p: p.get("additionalAttributes")).get("additionalAttributes") == {"userVars.example_k": "v"})
        listed = [p["name"] for p in (admin.get("transferProfiles", params={"account": RECEIVER, "additionalAttributes.key": "userVars.example_k",
                                                                                   "fields": "name"}).json() or {}).get("result", [])]
        c.check("and the list can be filtered by that attribute", UPPER in listed and EXAMPLE not in listed, listed)

        # -- 01: the list, and the default -----------------------------------------------
        c.info("--- 01 lists, and an account has at most one default profile")
        for profile in (EXAMPLE, UPPER):
            admin.patch("transferProfiles/" + find(RECEIVER, profile)["id"], [{"op": "replace", "path": "/default", "value": True}])
        defaults = settled(RECEIVER, EXAMPLE, lambda p: p.get("default") is False)
        c.check("making a second profile the default turns the first one off",
                find(RECEIVER, UPPER).get("default") is True and defaults.get("default") is False,
                [(p["name"], p["default"]) for p in profiles(RECEIVER)])
        out = script("01.transferProfiles_GET.sh", [RECEIVER, "example*"])
        total = (admin.get("transferProfiles", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount")
        everything, only_default = out.split("Only the default ones:")
        c.check("01 prints the count the API gives", "Transfer profiles on the server: %s" % total in everything, (total, everything[:100]))
        c.check("01 lists both profiles of the account, and 'default' on the capitals one only",
                "%s/%s  default" % (RECEIVER, UPPER) in everything and "%s/%s  -" % (RECEIVER, EXAMPLE) in everything, everything[-500:])
        c.check("01 lists only that one under the default ones", UPPER in only_default and "%s/%s" % (RECEIVER, EXAMPLE) not in only_default, only_default)
        junk = [p["name"] for p in (admin.get("transferProfiles", params={"account": RECEIVER, "default": "abc", "fields": "name"}).json() or {}).get("result", [])]
        c.check("default=abc is taken as false (it lists the profiles that are not the default)", UPPER not in junk and EXAMPLE in junk, junk)
        c.check("the account filter is exact: capitals and a wildcard find nothing",
                not profiles(RECEIVER.lower()) and not (admin.get("transferProfiles", params={"account": RECEIVER[:-1] + "*"}).json() or {}).get("result"))
        wild = sorted(p["name"] for p in (admin.get("transferProfiles", params={"account": RECEIVER, "name": "Example_P*", "fields": "name"}).json() or {}).get("result", []))
        c.check("the name filter ignores case and takes a *", wild == sorted([EXAMPLE, UPPER]), wild)
        limit = admin.get("transferProfiles", params={"limit": -1})
        c.check("a negative limit is 400", limit.status == 400, limit.text[:200])
        field = admin.get("transferProfiles", params={"fields": "nope"})
        c.check("an unknown field is 400", field.status == 400 and "does not exist" in field.text, field.text[:200])

        # -- what a profile does to a real transfer -------------------------------------------
        c.info("--- a profile at work: a PeSIT pull, twice")
        eu_sender = st_client.EndUserClient(HOST, ENDUSER_PORT, SENDER, PASSWORD)
        eu_sender.login()
        eu_receiver = st_client.EndUserClient(HOST, ENDUSER_PORT, RECEIVER, PASSWORD)
        eu_receiver.login()
        sent = eu_sender.upload("/" + SENT_FILE, b"A file for the transfer profile check.\n", SENT_FILE)
        c.check("set up: the sender holds the file", sent.status in (200, 201, 204), sent.status)
        landing = eu_receiver.create_folder("landing")
        c.check("set up: the receiver has a /landing folder", landing.status in (200, 201), landing.status)
        made_send = admin.post("transferProfiles", {"name": SEND_PROFILE, "account": SENDER, "default": True, "sendMapping": "/" + SENT_FILE,
                                                    "receiveMapping": "${pesit.fileName}", "fileLabelOption": "SEND_FILENAME", "advancedSettings": BINARY_ADV})
        c.check(core("set up: the sender's default profile (advanced, binary) names the file to send"), made_send.status == 201, made_send.text[:200])
        out = script("02.transferProfiles_POST.sh", [RECEIVER, FIXED_PROFILE, "/x", FIXED_NAME])
        script("02.transferProfiles_POST.sh", [RECEIVER, BASIC_PROFILE, "/x", BASIC_LANDED, "basic"])
        made_default = admin.post("transferProfiles", {"name": DEFAULT_PROFILE, "account": RECEIVER, "default": True, "sendMapping": "/x",
                                                       "receiveMapping": "${pesit.fileName}", "fileLabelOption": "DONT_SEND", "advancedSettings": BINARY_ADV})
        c.check(core("set up: the receiver's default profile (the file takes the profile's name)"), made_default.status == 201, made_default.text[:200])

        index, rows = pull(FIXED_PROFILE)
        c.check(core("pull naming %s (advancedSettings, binary): Processed" % FIXED_PROFILE), bool(rows) and rows[0]["status"] == "Processed", [(r["status"], r.get("filename")) for r in rows])
        c.check("   its transfer log entry carries the profile's name as the PeSIT file name", bool(rows) and rows[0].get("filename") == FIXED_PROFILE, rows and rows[0].get("filename"))
        names = harness.wait_until(lambda: FIXED_NAME in (eu_receiver.list_folder("/landing") or []), 30) and eu_receiver.list_folder("/landing")
        c.check("   the file landed in /landing under the receive mapping of the profile named", bool(names) and FIXED_NAME in names, names)
        landed.append(FIXED_NAME)

        index, rows = pull()
        c.check("pull naming no profile: Processed", bool(rows) and rows[0]["status"] == "Processed", [(r["status"], r.get("filename")) for r in rows])
        names = harness.wait_until(lambda: DEFAULT_PROFILE in (eu_receiver.list_folder("/landing") or []), 30) and eu_receiver.list_folder("/landing")
        c.check("   it used the account's default profile: the file is called %s, the profile's name" % DEFAULT_PROFILE, bool(names) and DEFAULT_PROFILE in names, names)
        landed.append(DEFAULT_PROFILE)
        index, rows = pull(BASIC_PROFILE)
        c.check(extra("pull naming %s (a profile with the plain fields only): Processed" % BASIC_PROFILE), bool(rows) and rows[0]["status"] == "Processed", [(r["status"], r.get("filename")) for r in rows])
        names = harness.wait_until(lambda: BASIC_LANDED in (eu_receiver.list_folder("/landing") or []), 30) and eu_receiver.list_folder("/landing")
        c.check(extra("   the file landed under that basic profile's receive mapping"), bool(names) and BASIC_LANDED in names, names)
        landed.append(BASIC_LANDED)
        c.check("   the sender's file is still there (the site keeps it: PRESERVE)", SENT_FILE in (eu_sender.list_folder("/") or []))

        # -- 07: DELETE -------------------------------------------------------------------
        c.info("--- 07 deletes the one profile it names")
        out = script("07.transferProfiles_id_DELETE.sh", [RECEIVER, EXAMPLE])
        gone = harness.wait_until(lambda: find(RECEIVER, EXAMPLE) is None)
        c.check("07 deleted example_profile (204) and no other: the one in capitals is still there",
                gone and "HTTP 204" in out and find(RECEIVER, UPPER) is not None, out[-300:])
        script("07.transferProfiles_id_DELETE.sh", [RECEIVER, EXAMPLE], expect_rc=1, retry=False)
        script("07.transferProfiles_id_DELETE.sh", [RECEIVER], expect_rc=2)
        script("07.transferProfiles_id_DELETE.sh", [RECEIVER, UPPER])
        again = admin.delete("transferProfiles/" + made["id"])
        c.check("DELETE of a profile that is already gone is a JSON 404", again.status == 404 and "not found" in again.text, again.text[:200])
        script("07.transferProfiles_id_DELETE.sh", [RECEIVER, SACRIFICE])
        script("07.transferProfiles_id_DELETE.sh", [RECEIVER, FIXED_PROFILE])
        for extra_name in (ASCII_NAME, "example_ebcdic", BASIC_NAME, BASIC_PROFILE):
            script("07.transferProfiles_id_DELETE.sh", [RECEIVER, extra_name])
        c.check("only the receiver's default profile is left",
                harness.wait_until(lambda: [p["name"] for p in profiles(RECEIVER)] == [DEFAULT_PROFILE]), [p["name"] for p in profiles(RECEIVER)])
finally:
    # the files first: the home folders stay on disk when the accounts go
    for client, folder_files in ((eu_receiver, ["landing/" + n for n in landed] + ["landing"]), (eu_sender, [SENT_FILE])):
        if client:
            for path in folder_files:
                client.delete_file(path)
            client.logout()
    for account in accounts:
        for p in profiles(account):
            admin.delete("transferProfiles/" + p["id"])
        for s in (admin.get("sites", params={"account": account, "fields": "id"}).json() or {}).get("result", []):
            admin.delete("sites/" + s["id"])
    user_accounts.close()
    c.check("nothing is left behind: no profile of ours, no account",
            harness.wait_until(lambda: not (admin.get("transferProfiles", params={"name": "example_*"}).json() or {}).get("result")
                       and not any(profiles(a) for a in accounts) and not any(admin.exists("accounts/" + a) for a in accounts)))
    c.check("the profile count is as before",
            harness.wait_until(lambda: (admin.get("transferProfiles", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount") == before),
            (admin.get("transferProfiles", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount"))
    admin.logout()

sys.exit(c.done())
