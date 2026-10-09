#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 24.IcapServers examples in two
parts.

1. The examples themselves, with disabled servers pointing nowhere: add, list
   and filter, check, read, replace, change and delete, a name with a space, and
   the arguments each one refuses. A PUT is checked to leave the name alone, and
   a delete is checked to succeed even for a server a business unit lists.

2. What an ICAP server is for. A FakeIcap (tests/integration/lib/dummy_servers.py)
   on this machine plays the antivirus; the server is added with the real
   example, enabled with the real PATCH example, and listed by a throwaway
   business unit, which has a throwaway end user account in it. Files are
   uploaded with the real EndUser example:
     - a clean file is let through, a file with the marker text is blocked (the
       transfer ends Failed and the file is removed);
     - with the ICAP server gone, a file goes through when denyOnConnectionError
       is false and is refused when it is true;
     - with the server disabled, nothing is scanned.
   The server is enabled only for that business unit, so no other transfer on
   the server is scanned.

Part 2 needs st_callback_host in integration.conf: this machine's address as the
server sees it (see integration.conf.example); without it only part 1 runs.
Needs --write and st_allow_writes="yes". Refuses to start when its example_icap*
objects exist, and removes everything in a finally block.
"""
import base64
import contextlib
import os
import sys
import tempfile
from urllib.parse import quote

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402
import dummy_servers  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the ICAP server examples for real")

c = st_client.Checker("ICAP servers, run for real from Admin/API 2.0/bash/24.IcapServers")
ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
FOLDER = os.path.join(ADMIN_TREE, "24.IcapServers")
NAME, SPACED, BEHAVIOUR = "example_icap", "example icap space", "example_icap_scan"
RUN = harness.suffix(8)
BU, ACCOUNT = "example_icap_bu", "example_icap_user_" + RUN
PASSWORD = harness.new_password()
ENDUSER_PORT = harness.ports(config).enduser
CALLBACK = config.get("st_callback_host", "")


script = harness.bind_script(c, FOLDER, timeout=90)


def server(name):
    response = admin.get("icapServers/" + quote(name, safe=""))
    return response.json() if response.status == 200 else None


def upload(local_name, content):
    with tempfile.TemporaryDirectory() as work:
        path = os.path.join(work, local_name)
        with open(path, "wb") as f:
            f.write(content)
        with runner.real_credentials(ENDUSER_TREE, dict(config, st_port=ENDUSER_PORT, st_user=ACCOUNT, st_password=PASSWORD)):
            return runner.run(os.path.join(ENDUSER_TREE, "02.Files", "08.fileOperations_POST_upload.sh"), [path], timeout=90)


def look(filename):
    """One reading: (is the file still in the home folder, the newest transfer status for it)."""
    client = st_client.EndUserClient(config["st_server"], ENDUSER_PORT, ACCOUNT, PASSWORD)
    client.login()
    present = filename in (client.list_folder("") or [])
    client.logout()
    logged = admin.get("logs/transfers", params={"account": ACCOUNT, "limit": 50}).json().get("result", [])
    status = next((x["status"] for x in logged if x["filename"] == filename), None)
    return present, status


def verdict(filename, until, timeout=45):
    """The reading (is the file still in the home folder, its newest transfer status) once `until(reading)` holds, or
    the last reading after `timeout` seconds. The scan and the transfer log take a moment: the state is waited for,
    not a fixed time."""
    return harness.settled(lambda: look(filename), until, timeout, 2)


GONE = lambda reading: not reading[0]  # noqa: E731
PASSED = lambda reading: reading == (True, "Processed")  # noqa: E731


admin = harness.connect(config, c, mock="the bundled mock does not implement /icapServers")
if any(server(n) for n in (NAME, SPACED, BEHAVIOUR)) or admin.exists("businessUnits/" + BU) or admin.exists("accounts/" + ACCOUNT):
    c.check("no example_icap* server, unit or account exists yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

icap = None
accounts = contextlib.ExitStack()
try:
    with runner.real_credentials(ADMIN_TREE, config):
        # ---- part 1: the examples
        out = script("02.icapServers_POST.sh")
        made = server(NAME)
        c.check("02 added example_icap, disabled, INCOMING, with the default address",
                made and (made["serverEnabled"], made["basicSettings"]["type"], made["basicSettings"]["url"]) == (False, "INCOMING", "icap://icap.example.com:1344/AVSCAN"), made)
        c.check("02 printed where it is, from Location", "It is at" in out and "/icapServers/%s" % NAME in out, out[-200:])
        script("02.icapServers_POST.sh", [SPACED, "icap://spaced.example.com:1344/REQMOD", "BOTH"])
        c.check("02 a name with a space, type BOTH", (server(SPACED) or {}).get("basicSettings", {}).get("type") == "BOTH")
        script("02.icapServers_POST.sh", expect_rc=1)
        total = admin.get("icapServers").json()["resultSet"]["totalCount"]
        for args in (["a/b"], ["a;b"], ["x", "http://x"], ["x", "icap://h/s", "SIDEWAYS"], [" "]):
            script("02.icapServers_POST.sh", args, expect_rc=2)
        c.check("02 a name that exists, a bad name, address or type sent nothing", admin.get("icapServers").json()["resultSet"]["totalCount"] == total)

        out = script("01.icapServers_GET.sh", [NAME, "INCOMING"])
        c.check("01 lists them, with type, address and enabled", "  %s  INCOMING  icap://icap.example.com:1344/AVSCAN  disabled" % NAME in out, out[-500:])
        c.check("01 one by its exact name", "The one named %s:\n  %s  " % (NAME, NAME) in out and "The one named" in out, out[-500:])
        c.check("01 and only the INCOMING type", out.split("Only the ones of type INCOMING:")[-1].count("  %s  " % SPACED) == 0)
        c.check("01 neither is in the enabled list", "Only the enabled ones:\n\n" in out, out[-500:])
        script("01.icapServers_GET.sh", ["", "SIDEWAYS"], expect_rc=2)

        out = script("03.icapServers_name_HEAD.sh")
        c.check("03 finds example_icap", "exists" in out, out[-200:])
        script("03.icapServers_name_HEAD.sh", [SPACED])
        script("03.icapServers_name_HEAD.sh", ["example_icap_nope"], expect_rc=1)
        out = script("04.icapServers_name_GET.sh", [SPACED])
        c.check("04 reads the server with a space in its name", "  %s: BOTH icap://spaced.example.com:1344/REQMOD, disabled" % SPACED in out, out[-500:])

        script("05.icapServers_name_PUT.sh", [NAME, "25"])
        now = server(NAME)
        c.check("05 PUT changed maxSize and kept the name and everything else",
                now and (now["basicSettings"]["name"], now["basicSettings"]["maxSize"], now["basicSettings"]["previewSize"], now["serverEnabled"]) == (NAME, 25, 1024, False), now)
        script("05.icapServers_name_PUT.sh", ["example_icap_nope"], expect_rc=1)
        script("05.icapServers_name_PUT.sh", [NAME, "many"], expect_rc=2)
        script("06.icapServers_name_PATCH.sh", [NAME, "true", "true"])
        now = server(NAME)
        c.check("06 PATCH enabled it and set deny when unreachable", now and (now["serverEnabled"], now["basicSettings"]["denyOnConnectionError"]) == (True, True), now)
        script("06.icapServers_name_PATCH.sh", [NAME])
        now = server(NAME)
        c.check("06 with no arguments it disables, and leaves the deny setting", now and (now["serverEnabled"], now["basicSettings"]["denyOnConnectionError"]) == (False, True), now)
        script("06.icapServers_name_PATCH.sh", [NAME, "maybe"], expect_rc=2)
        script("06.icapServers_name_PATCH.sh", ["example_icap_nope"], expect_rc=1)

        c.check("set up: a business unit that lists example_icap",
                admin.post("businessUnits", {"name": BU, "baseFolder": "/home/%s_%s" % (BU, RUN), "enabledIcapServers": [NAME]}).status == 201)
        out = script("04.icapServers_name_GET.sh", [NAME])
        c.check("04 lists the business unit that enables the server", "\n  %s\n" % BU in out + "\n", out[-300:])
        c.check("04 and not the others", out.split("so whose transfers it scans:")[-1].strip() == BU, out[-300:])
        script("07.icapServers_name_DELETE.sh")
        c.check("07 deleted example_icap, though a business unit listed it", server(NAME) is None)
        c.check("07 and it was taken out of that unit's list", admin.get("businessUnits/" + BU).json().get("enabledIcapServers") == [])
        script("07.icapServers_name_DELETE.sh", expect_rc=1)
        script("07.icapServers_name_DELETE.sh", [SPACED])
        c.check("07 deleted the server with a space in its name", server(SPACED) is None)
        admin.delete("businessUnits/" + BU)

        # ---- part 2: what a server is for
        if not CALLBACK:
            c.info("st_callback_host is not set: the scan itself (part 2) is skipped")
        else:
            icap = dummy_servers.FakeIcap()
            icap.__enter__()
            url = "icap://%s:%d/AVSCAN" % (CALLBACK, icap.port)
            script("02.icapServers_POST.sh", [BEHAVIOUR, url, "INCOMING"])
            script("06.icapServers_name_PATCH.sh", [BEHAVIOUR, "true", "false"])
            c.check("set up: the server is enabled, and does not deny when unreachable",
                    (server(BEHAVIOUR) or {}).get("serverEnabled") is True and not server(BEHAVIOUR)["basicSettings"]["denyOnConnectionError"])
            c.check("set up: a business unit that lists it",
                    admin.post("businessUnits", {"name": BU, "baseFolder": "/home/%s_%s" % (BU, RUN), "enabledIcapServers": [BEHAVIOUR]}).status == 201)
            accounts.enter_context(harness.throwaway_account(
                admin, c, config, name=ACCOUNT, password=PASSWORD, home="/home/%s_%s/%s" % (BU, RUN, ACCOUNT),
                extra={"businessUnit": BU}, label="set up: an end user account in that unit"))

            c.check("a clean file is uploaded", upload("a_clean.txt", b"nothing wrong in here\n").returncode == 0)
            c.check("a file with the marker text is uploaded", upload("a_marked.txt", b"this holds EICAR-ICAP-TEST, so block it\n").returncode == 0)
            marked = verdict("a_marked.txt", GONE)
            clean = verdict("a_clean.txt", PASSED)
            c.check("the ICAP server was sent both files, one of them blocked (they may arrive in either order)",
                    sorted((r["method"], r["blocked"]) for r in icap.requests) == [("REQMOD", False), ("REQMOD", True)],
                    [(r["method"], r["blocked"]) for r in icap.requests])
            c.check("it asked for the server's options first", len(icap.options) >= 1)
            c.check("the clean file is let through: still there, transfer Processed", clean == (True, "Processed"), clean)
            c.check("the file with the marker is blocked: removed, transfer Failed", marked == (False, "Failed"), marked)
            c.check("it was sent as the account's own upload, with the authenticated user",
                    icap.requests and base64.b64decode(icap.requests[0]["icap_headers"].get("x-authenticated-user", "")) == b"Local://" + ACCOUNT.encode(),
                    icap.requests and icap.requests[0]["icap_headers"].get("x-authenticated-user"))

            icap.__exit__(None, None, None)
            icap = None
            upload("b_down_allowed.txt", b"the scanner is down\n")
            allowed = verdict("b_down_allowed.txt", PASSED)
            c.check("with the ICAP server gone and deny off, the file goes through", allowed == (True, "Processed"), allowed)
            script("06.icapServers_name_PATCH.sh", [BEHAVIOUR, "true", "true"])
            upload("c_down_denied.txt", b"the scanner is down\n")
            denied = verdict("c_down_denied.txt", GONE)
            c.check("with the ICAP server gone and deny on, the file is refused: removed, Failed", denied == (False, "Failed"), denied)
            script("06.icapServers_name_PATCH.sh", [BEHAVIOUR, "false"])
            upload("d_disabled.txt", b"nothing scans this\n")
            disabled = verdict("d_disabled.txt", PASSED)
            c.check("with the server disabled, the file goes through though deny is on", disabled == (True, "Processed"), disabled)
finally:
    if icap is not None:
        icap.__exit__(None, None, None)
    accounts.close()   # its files, then the account
    admin.delete("businessUnits/" + BU)
    for name in (NAME, SPACED, BEHAVIOUR):
        admin.delete("icapServers/" + quote(name, safe=""))
    c.check("nothing is left behind: no server, business unit or account",
            not any(server(n) for n in (NAME, SPACED, BEHAVIOUR)) and not admin.exists("businessUnits/" + BU) and not admin.exists("accounts/" + ACCOUNT))
    admin.logout()

sys.exit(c.done())
