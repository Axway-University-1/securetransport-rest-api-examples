#!/usr/bin/env python3
"""
WRITES TO THE SERVER, AND CHANGES THE SENTINEL SETTINGS OF THE WHOLE SERVER and the Fusion options for the time of the run (a throwaway account, example_qlt, with its objects, the Sentinel host, port and
overflow file, and a Fusion integration, which it puts back and compares), and starts a fake HTTP server on this machine. Runs Admin/UseCases/10-qlt-events-generation for real, as the administrator of
the configuration.

It proves what the use case and its README say, through its own reads of the Sentinel settings, of the Fusion options, of the transfer log and of the overflow files, and not through the scripts. Before
anything it keeps the Sentinel settings and the Fusion options. A whole run (00.run_all.sh) exits 0, shows for the push the events of the upload and of the push under one coreId and the request the fake server
was sent, and for the Fusion scenario the call to Fusion and the second push; every state is on; the settings and the Fusion options read back identical. Then the steps one at a time, to read the case
files here: each holds the flow of its scenario and nothing of the other, the events of reading them are in the reads file, and the overflow file points to the reads file in between. At the end, whatever
happened, the settings and the Fusion options are put back from the copy this check made, and compared.

Needs --write and st_allow_writes="yes", st_callback_host (the address of this machine as the server sees it) and the End User port (st_enduser_port, or the admin port minus one). It does not run on the
bundled mock, which has no Sentinel settings, overflow file or routes of this kind.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the QLT events use case for real")
if not config.get("st_callback_host"):
    st_client.skip("st_callback_host is not set in integration.conf: the fake HTTP server runs on this machine and the server must reach it")

c = st_client.Checker("Admin use case 10-qlt-events-generation, run for real")
ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
UC = runner.path("Admin", "UseCases", "10-qlt-events-generation")
S1 = os.path.join(UC, "1-upload-push")
S2 = os.path.join(UC, "2-upload-fusion-partner")
ACCOUNT = "example_qlt"
CASE1, CASE2, READS = "qlt_1_upload_push.dat", "qlt_2_upload_fusion_partner.dat", "qlt_reads.dat"
ENV = {"ST_ENDUSER_PORT": harness.ports(config).enduser, "ST_CALLBACK_HOST": config["st_callback_host"]}
STATE_GLOBS = ("state.local.",)

admin = harness.connect(config, c, mock="the bundled mock has no Sentinel settings, overflow file or Advanced Routing of this kind; run this against a real server to exercise it")


def clear_local():
    for folder in (UC, S1, S2):
        for leftover in os.listdir(folder):
            if leftover.startswith(STATE_GLOBS) or leftover == "session.cookie.jar":
                os.remove(os.path.join(folder, leftover))


def sentinel():
    return admin.get("configurations/sentinel").json()


def fusion():
    return {o["name"]: o["values"] for o in admin.results("configurations/options", {"name": "Fusion.Integrations*", "limit": 200})}


def our_objects():
    found = []
    for resource, key in (("sites", "name"), ("routes", "name"), ("applications", "name")):
        found += [x[key] for x in admin.results(resource, {"name": "example_qlt_*", "limit": 100}) if str(x.get(key, "")).startswith("example_qlt_")]
    return found


def events_of(data):
    """Each event of an overflow file as (kind, attributes), read here and not by the scripts: cut at the closing tag."""
    out = []
    for part in data.split(b"</TrkDescriptor>")[:-1]:
        i = part.rfind(b"<?xml")
        if i < 0:
            continue
        text = part[i:].decode("utf-8", "replace")
        kind = re.search(r' NAME="([^"]+)"', text.split("<TrkAttr")[0]) or re.search(r' type="([^"]+)"', text.split("<TrkAttr")[0])
        out.append((kind.group(1) if kind else "?", dict(re.findall(r'<TrkAttr name="([^"]+)" val="([^"]*)"', text))))
    return out


def read_file(name, password):
    eu = st_client.EndUserClient(config["st_server"], ENV["ST_ENDUSER_PORT"], ACCOUNT, password)
    eu.login()
    try:
        r = eu.download(name)
        return r.status, (r.body or b"")
    finally:
        eu.logout()


def stateful(events):
    return [(a.get("STATE"), a.get("DIRECTION"), a.get("PROTOCOLFILENAME")) for kind, a in events if kind == "XFBTransfer"]


def fake_servers():
    import subprocess
    out = subprocess.run(["ps", "-axo", "command="], capture_output=True, text=True).stdout
    return [line for line in out.splitlines() if "fake_http_server.py" in line and ENV and "state.local.fake_server.log" in line]


try:
    if admin.exists("accounts/" + ACCOUNT) or our_objects():
        c.info("the account %s or objects named example_qlt_* are on the server already (%s); skipping rather than reuse them" % (ACCOUNT, ", ".join(our_objects())))
        admin.logout()
        sys.exit(c.done())
    before = sentinel()
    fusion_before = fusion()
    c.check("the Sentinel settings and the Fusion options are read before anything is changed", isinstance(before, dict) and "host" in before and "Fusion.Integrations.Registry" in fusion_before, str(before)[:200])
    clear_local()

    with runner.real_credentials(ADMIN_TREE, config):
        # -- 03 without the copy of 02 ------------------------------------------------------------------------
        r = runner.run(os.path.join(UC, "03.sentinel_PATCH.sh"), timeout=60, env=ENV)
        c.check("03 with no copy of the settings: exit 1, 'run 02.sentinel_GET.sh first'", r.returncode == 1 and "run 02.sentinel_GET.sh first" in r.stdout, (r.returncode, r.stdout[-200:]))
        c.check("... and the settings are as they were", sentinel() == before)

        # -- a whole run ---------------------------------------------------------------------------------------
        r = runner.run(os.path.join(UC, "00.run_all.sh"), timeout=1500, env=ENV)
        out = r.stdout
        c.check("00.run_all.sh exits 0", r.returncode == 0, (out + r.stderr).strip()[-900:])
        c.check("it ended with the cleanup", "Cleaned up." in out, out[-200:])
        c.check("03: it reported to 192.0.2.1:1305 and every state is on", "reporting: on, to 192.0.2.1:1305" in out and re.search(r"states reported: (\d+) of \1", out), out[:2500])
        first, second = out.split("=== 2-upload-fusion-partner/01.objects_POST ===")[0], out.split("=== 2-upload-fusion-partner/01.objects_POST ===")[1]
        c.check("scenario 1: the table has RECEIVING, RECEIVED, SENDING and SENT of the file, a CycleLink and the route's event",
                all(re.search(r"XFBTransfer\s+%s\s" % s, first) for s in ("RECEIVING", "RECEIVED", "SENDING", "SENT")) and "CycleLink" in first and "XFBRouting" in first, first[-2500:])
        c.check("scenario 1: the fake server was sent one PUT /upload with the file, answered 200", re.search(r"PUT /upload\s+\d+ bytes\s+the file push_\d+\.txt\s+answered 200", first), first[-800:])
        c.check("scenario 1: the coreIds of the file's events are one", len({m for m in re.findall(r"XFBTransfer\s+\S+\s+[RS ]\s+push_\d+\.txt\s+(\S+)", first)}) == 1, first[-2500:])
        c.check("scenario 1: the ties to the log: every transfer has events with its coreId", "Every transfer of the flow in the log has events that carry its coreId." in first, first[-900:])
        c.check("scenario 2: the fake server was sent the call to Fusion (POST /fusion) and then the file (PUT /upload)",
                re.search(r"POST /fusion\s+\d+ bytes\s+the file fusion_\d+\.txt\s+answered 200", second) and re.search(r"PUT /upload\s+\d+ bytes\s+the file fusion_response_\d+\.dat\s+answered 200", second), second[-1200:])
        c.check("scenario 2: the table shows the file Fusion sent back received and then sent on (RECEIVING and SENT of fusion_response)",
                re.search(r"XFBTransfer\s+RECEIVING\s+R\s+fusion_response", second) and re.search(r"XFBTransfer\s+SENT\s+S\s+fusion_response", second), second[:3500])
        c.check("scenario 2: the Fusion options are put back and compared: 'the same as before'", "The Fusion options read back are the same as before, key by key." in second, second[-900:])
        c.check("99: the settings read back are the same as the copy", "The settings read back are the same as the copy, key by key." in out, out[-700:])
        c.check("the settings are identical to the ones kept before: every key, read here and not by the script", sentinel() == before,
                {k: (before.get(k), sentinel().get(k)) for k in set(before) | set(sentinel()) if before.get(k) != sentinel().get(k)})
        c.check("the Fusion options are identical to the ones kept before, read here", fusion() == fusion_before, {k: (fusion_before.get(k), fusion().get(k)) for k in set(fusion_before) | set(fusion()) if fusion_before.get(k) != fusion().get(k)})
        c.check("no account, no object named example_qlt_*, no state file and no fake server is left", not admin.exists("accounts/" + ACCOUNT) and not our_objects()
                and not any(f.startswith("state.local.") for d in (UC, S1, S2) for f in os.listdir(d)) and not fake_servers(), (our_objects(), fake_servers()))

        # -- the steps one at a time: the two case files are apart -----------------------------------------------
        for step in ("01.accounts_POST.sh", "02.sentinel_GET.sh", "03.sentinel_PATCH.sh", "04.fakeServer_start.sh"):
            r = runner.run(os.path.join(UC, step), timeout=180, env=ENV)
            c.check("%s exits 0" % step, r.returncode == 0, (r.stdout + r.stderr)[-400:])
        kept = json.load(open(os.path.join(UC, "state.local.sentinel.json"), encoding="utf-8"))
        c.check("02: the copy is the settings of the server, as read here", kept == before)
        now = sentinel()
        c.check("03: every state of the settings is on, reading them back here; the overflow file is the reads file of the account", all(v != "false" for v in now["eventStates"].values())
                and now["overflowFilePath"] == "/home/example_qlt/" + READS and (now["host"], now["port"], now["enabled"]) == ("192.0.2.1", 1305, True), now)
        r = runner.run(os.path.join(UC, "03.sentinel_PATCH.sh"), timeout=60, env=ENV)
        c.check("03 again is fine: exit 0, and nothing is left to turn on", r.returncode == 0 and "turning on 0 state(s)" in r.stdout, r.stdout[-300:])
        for folder in (S1, S2):
            for step in ("01.objects_POST.sh", "02.flow_POST.sh"):
                r = runner.run(os.path.join(folder, step), timeout=400, env=ENV)
                c.check("%s/%s exits 0" % (os.path.basename(folder), step), r.returncode == 0, (r.stdout + r.stderr)[-500:])
                if step == "02.flow_POST.sh":
                    c.check("%s: after the flow the overflow file is the reads file again, read here" % os.path.basename(folder), sentinel()["overflowFilePath"] == "/home/example_qlt/" + READS, sentinel().get("overflowFilePath"))
        password = open(os.path.join(UC, "state.local.password"), encoding="utf-8").read()
        upload1 = open(os.path.join(S1, "state.local.upload"), encoding="utf-8").read().strip()
        upload2 = open(os.path.join(S2, "state.local.upload"), encoding="utf-8").read().strip()
        status1, data1 = read_file(CASE1, password)
        status2, data2 = read_file(CASE2, password)
        c.check("both case files are there", (status1, status2) == (200, 200), (status1, status2))
        ev1, ev2 = events_of(data1), events_of(data2)
        names1 = {a.get("PROTOCOLFILENAME") for k, a in ev1 if k == "XFBTransfer"} - {None, ""}
        names2 = {a.get("PROTOCOLFILENAME") for k, a in ev2 if k == "XFBTransfer"} - {None, ""}
        c.check("case file 1 holds the push flow: the events of %s, and no file of scenario 2" % upload1, upload1 in names1 and not any(n.startswith("fusion") for n in names1), names1)
        c.check("case file 2 holds the Fusion flow: the events of %s and of the file Fusion sent back, and no file of scenario 1" % upload2,
                upload2 in names2 and any(n.startswith("fusion_response") for n in names2) and not any(n.startswith("push_") for n in names2), names2)
        c.check("neither case file holds the reading of a file: no event of qlt_*.dat in them", not any(n.startswith("qlt_") for n in names1 | names2), (names1, names2))
        c.check("each XFBTransfer event of a file has the one coreId of its flow", len({a.get("COREID") for k, a in ev1 if k == "XFBTransfer" and a.get("PROTOCOLFILENAME") == upload1}) == 1
                and len({a.get("COREID") for k, a in ev2 if k == "XFBTransfer" and a.get("PROTOCOLFILENAME") == upload2}) == 1)
        status3, data3 = read_file(READS, password)
        names3 = {a.get("PROTOCOLFILENAME") for k, a in events_of(data3) if k == "XFBTransfer"}
        c.check("the reads file holds the events of the two reads (the downloads of the case files), made after the overflow file was turned to it", status3 == 200 and {CASE1, CASE2} <= names3, (status3, names3))
        window = open(os.path.join(S1, "state.local.window"), encoding="utf-8").read().strip()
        log = admin.results("logs/transfers", {"account": ACCOUNT, "startTimeAfter": window, "limit": 100})
        core1 = {t.get("coreId") for t in log if t.get("filename") == upload1}
        core2 = {t.get("coreId") for t in log if t.get("filename") == upload2}
        c.check("the transfer log, read here, has the coreId of each flow, and it is the one on the events", core1 == {a.get("COREID") for k, a in ev1 if a.get("PROTOCOLFILENAME") == upload1 and a.get("COREID")}
                and core2 == {a.get("COREID") for k, a in ev2 if a.get("PROTOCOLFILENAME") == upload2 and a.get("COREID")} and len(core1) == len(core2) == 1, (core1, core2))
        r = runner.run(os.path.join(S1, "03.events_GET.sh"), ["raw"], timeout=300, env=ENV)
        c.check("1/03 raw prints what an event carries: the state, the coreId, the file", r.returncode == 0 and re.search(r"^\s+STATE\s+RECEIVED$", r.stdout, re.M) and re.search(r"^\s+COREID\s+[0-9a-f-]{36}$", r.stdout, re.M), r.stdout[-600:])
        r = runner.run(os.path.join(S1, "02.flow_POST.sh"), timeout=400, env=ENV)
        c.check("1/02 run again: the case file of the first run is deleted and the flow is clean (a new file name)", r.returncode == 0 and "starts clean" in r.stdout, (r.returncode, r.stdout[-400:]))
        for folder in (S1, S2):
            r = runner.run(os.path.join(folder, "99.objects_DELETE.sh"), timeout=180, env=ENV)
            c.check("%s/99 exits 0" % os.path.basename(folder), r.returncode == 0, r.stdout[-400:])
        c.check("the Fusion options are identical to the ones kept before, read here", fusion() == fusion_before)
        r = runner.run(os.path.join(UC, "99.cleanup_DELETE.sh"), timeout=300, env=ENV)
        c.check("99: exit 0, the settings and the Fusion options are identical to the ones kept before, no account and no fake server is left", r.returncode == 0 and sentinel() == before and fusion() == fusion_before
                and not admin.exists("accounts/" + ACCOUNT) and not fake_servers(), (r.returncode, r.stdout[-500:]))
        r = runner.run(os.path.join(UC, "99.cleanup_DELETE.sh"), timeout=300, env=ENV)
        c.check("99 a second time, with nothing to remove, exits 0 and leaves the settings alone", r.returncode == 0 and "There is no copy of the settings" in r.stdout and sentinel() == before, r.stdout[-300:])
finally:
    # Whatever happened above, the settings and the Fusion options go back to the ones kept at the start of this check, and the objects and the fake server are removed
    try:
        if "before" in globals() and isinstance(before, dict) and "host" in before and sentinel() != before:
            r = admin.put("configurations/sentinel", before)
            c.check("a safeguard: the settings were not the ones kept, and are put back from the copy of this check (%s)" % r.status, r.status == 204 and sentinel() == before)
        if "fusion_before" in globals() and fusion() != fusion_before:
            r = admin.put("configurations/options", [{"name": "Fusion.Integrations.Registry", "values": fusion_before["Fusion.Integrations.Registry"] or [""]}])
            c.check("a safeguard: the Fusion options were not the ones kept, and are put back (%s)" % r.status, r.status == 204 and fusion() == fusion_before)
    finally:
        if os.path.exists(os.path.join(UC, "state.local.fake_server.pid")) or any(os.path.exists(os.path.join(d, "state.local.objects")) for d in (S1, S2)):
            try:
                with runner.real_credentials(ADMIN_TREE, config):
                    runner.run(os.path.join(UC, "99.cleanup_DELETE.sh"), timeout=300, env=ENV)
            except Exception:  # noqa: BLE001 - the cleanup of last resort must not hide the result
                pass
        clear_local()
        if admin.exists("accounts/" + ACCOUNT):
            admin.delete("accounts/" + ACCOUNT)
        admin.logout()

sys.exit(c.done())
