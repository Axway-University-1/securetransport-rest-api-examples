#!/usr/bin/env python3
"""
WRITES TO THE SERVER (it ends sessions, of its own throwaway accounts only).
Runs the real, unmodified 32.Sessions examples against live sessions. A session
exists only while a client is connected, so this builds them:

  two end user accounts, example_sess_target_<random> and example_sess_bystander_<random>
  (a new name and user id on every run);
  the target holds an FTP session (ftplib, idle), an HTTP one (an EndUser API
  login kept open) and an SSH one (the system sftp client, password given by
  SSH_ASKPASS; left out, with a note, when sftp is not there); the bystander
  holds an FTP session too. The logins are the shared lib/protocol_logins.py.

It lists them with 01 (by protocol, by user), reads one with 02, and ends them
with 03 one by one, checking each effect on the CLIENT: the idle FTP client
finds the connection closed, the EndUser API answers 401, the ssh process
exits. Every time it checks that the sessions it did not name are still there
(the bystander's FTP session answers, the target's other sessions stay listed),
that 03 refuses when the user given is not the session's owner, and that the
sessions that were open before the check began are still open afterwards. 04 and
05 are read, and the counts of 05 are compared with the list.

Other people's sessions: the lists are the whole server's. What is compared is
therefore only this check's own: 05's per class and protocol counts are compared by
how much they GREW since before the check opened its sessions against the number of
its own sessions in that class, and the lines of 01 and 05 against the server's
numbers read just before and just after the example ran (a session opening or
closing in that moment is allowed for). A session of somebody else that opens or
ends between the two reads of one moment still fails it: run it again.

Needs --write and st_allow_writes="yes". It only ever ends a session whose userName
is one of its two accounts, and removes the accounts in a finally block, closing
every client first.
"""
import contextlib
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402
import protocol_logins  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the sessions examples for real")

c = st_client.Checker("Sessions, run for real from Admin/API 2.0/bash/32.Sessions")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "32.Sessions")
SUFFIX = harness.suffix()
TARGET, BYSTANDER = "example_sess_target_" + SUFFIX, "example_sess_bystander_" + SUFFIX
OURS = (TARGET, BYSTANDER)
PASSWORD = harness.new_password()
HOST = config["st_server"]


script = harness.bind_script(c, FOLDER, timeout=60)


def sessions():
    response = admin.get("sessions")
    return response.json() if response.status == 200 and isinstance(response.json(), list) else []


def mine(protocol=None, user=None):
    return [s for s in sessions() if s["userName"] in OURS and (user is None or s["userName"] == user)
            and (protocol is None or s["protocol"] == protocol)]


def class_counts(protocol_counters):
    """{protocol: sessions} of the VirtClass entry of GET /sessions/statistics/userClass."""
    entry = next((k for k in protocol_counters if k["userClass"] == "VirtClass"), None)
    g = (entry or {}).get("globalLoggedInCounters", {})
    return {k: g.get(k, 0) for k in ("total", "ftp", "http", "ssh")}


def server_counts():
    return class_counts(admin.get("sessions/statistics/userClass").json())


def own_counts():
    """The same numbers for this check's own open sessions in VirtClass."""
    found = {"total": 0, "ftp": 0, "http": 0, "ssh": 0}
    for s in mine():
        if s["userClass"] == "VirtClass":
            found["total"] += 1
            found[s["protocol"].lower()] = found.get(s["protocol"].lower(), 0) + 1
    return found


admin = harness.connect(config, c, mock="the bundled mock does not implement /sessions or the protocol servers")
ports = harness.ports(config, admin)
daemons = admin.get("daemons").json()
if not ports.ftp or daemons.get("ftpStatus") != "Running":
    c.info("the FTP daemon is not running: this check needs it")
    admin.logout()
    sys.exit(c.done())

logins = protocol_logins.Logins(HOST, ports.ssh, ports.enduser, ports.ftp, PASSWORD)
others_before = sorted(s["id"] for s in sessions())
counts_before = server_counts()
accounts = contextlib.ExitStack()
ftp_target = ftp_bystander = enduser = ssh = None
try:
    for account in OURS:
        accounts.enter_context(harness.throwaway_account(admin, c, config, name=account, password=PASSWORD))

    # Real clients, which stay connected
    ftp_target = logins.open_login("FTP", TARGET)
    ftp_bystander = logins.open_login("FTP", BYSTANDER)
    try:
        enduser = logins.open_login("HTTP", TARGET)
        http_login = "ok"
    except st_client.STError as e:
        http_login = e
    c.check("set up: the target logs in to the EndUser API and stays logged in", http_login == "ok", http_login)
    want = {"FTP": 1, "HTTP": 1}
    if daemons.get("sshStatus") == "Running" and shutil.which("sftp"):
        ssh = logins.open_login("SFTP", TARGET)
        want["SSH"] = 1
    else:
        c.info("no sftp client or SSH daemon: the SSH session is left out")

    def counts():
        found = {}
        for s in mine(user=TARGET):
            found[s["protocol"]] = found.get(s["protocol"], 0) + 1
        return found
    c.check("the server lists the target's sessions: %s" % want, harness.wait_until(lambda: counts() == want), counts())
    c.check("and the bystander's FTP session", harness.wait_until(lambda: len(mine("FTP", BYSTANDER)) == 1), mine(user=BYSTANDER))
    if counts() != want:
        raise SystemExit(c.done())
    by_protocol = {s["protocol"]: s for s in mine(user=TARGET)}
    bystander = mine("FTP", BYSTANDER)[0]
    c.check("an id starts with its protocol: FTP:<hash>:<number>, HTTP:<hash>", by_protocol["FTP"]["id"].startswith("FTP:")
            and by_protocol["FTP"]["id"].count(":") == 2 and by_protocol["HTTP"]["id"].startswith("HTTP:")
            and by_protocol["HTTP"]["id"].count(":") == 1, [s["id"] for s in mine()])
    c.check("the sessions carry the fields the example prints", all(k in by_protocol["FTP"] for k in
            ("id", "userName", "host", "protocol", "userClass", "currentTransferBandwidth", "command", "sessionCreationTime", "nodeIp", "serverName")),
            sorted(by_protocol["FTP"]))
    c.check("an idle FTP session runs IDLE", by_protocol["FTP"]["command"] == "IDLE", by_protocol["FTP"]["command"])

    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        # 01
        out = script("01.sessions_GET.sh")
        line = "  %s  %s  FTP  %s  IDLE  %s" % (by_protocol["FTP"]["id"], TARGET, by_protocol["FTP"]["host"], by_protocol["FTP"]["sessionCreationTime"])
        c.check("01 lists the target's FTP session: id, user, protocol, host, command, start", line in out, out[-600:])
        c.check("01 and the count line", "Sessions: %d" % len(sessions()) in out, out[:200])
        out = script("01.sessions_GET.sh", ["FTP"])
        c.check("01 FTP keeps the FTP sessions of both accounts, and not the HTTP one",
                by_protocol["FTP"]["id"] in out and bystander["id"] in out and by_protocol["HTTP"]["id"] not in out, out[-600:])
        out = script("01.sessions_GET.sh", ["all", BYSTANDER])
        c.check("01 with a user keeps that user's sessions only", bystander["id"] in out and by_protocol["FTP"]["id"] not in out, out[-400:])
        out = script("01.sessions_GET.sh", ["HTTP", BYSTANDER])
        c.check("01 a protocol and a user with no match is an empty list, exit 0", "Sessions: 0" in out, out[-200:])
        script("01.sessions_GET.sh", ["ftp"], expect_rc=2)
        # The server ignores type=: asked directly, every protocol comes back
        # The list itself is unstable (a call can lack sessions that are open, or be empty), so wait for a
        # moment when a call with type=SSH and one without both hold the target's sessions
        def listing(params=None):
            response = admin.get("sessions", params=params)
            found = response.json() if response.status == 200 and isinstance(response.json(), list) else []
            return {s["protocol"] for s in found if s["userName"] == TARGET}

        def both_complete():
            plain, filtered = listing(), listing({"type": "SSH"})
            both_complete.seen = (sorted(plain), sorted(filtered))
            return plain >= set(want) and filtered >= set(want)
        both_complete.seen = None
        c.check("the server ignores type=SSH (the target's FTP and HTTP sessions come back too): the reason 01 filters itself",
                harness.wait_until(both_complete, 30), both_complete.seen)

        # 02
        out = script("02.sessions_id_GET.sh", [by_protocol["HTTP"]["id"]])
        c.check("02 reads the HTTP session", "  HTTP session of %s from %s" % (TARGET, by_protocol["HTTP"]["host"]) in out, out[-300:])
        out = script("02.sessions_id_GET.sh")
        c.check("02 with no id it reads the first session listed", "session of" in out, out[-300:])
        out = script("02.sessions_id_GET.sh", ["FTP:" + "ab" * 32 + ":999"], expect_rc=1)
        c.check("02 a well formed id that is not there is refused with the server's reason", "was not found" in out, out[-300:])
        out = script("02.sessions_id_GET.sh", ["nosuch"], expect_rc=1)
        c.check("02 an id of the wrong shape is refused too (404 for a read)", "HTTP 404" in out and "format of the session is incorrect" in out, out[-300:])

        # 03: the guards first
        script("03.sessions_id_DELETE.sh", expect_rc=2)
        script("03.sessions_id_DELETE.sh", ["nocolon"], expect_rc=2)
        c.check("03 with no id, or a malformed one, nothing was ended", harness.wait_until(lambda: len(mine()) == len(want) + 1), len(mine()))
        out = script("03.sessions_id_DELETE.sh", [by_protocol["FTP"]["id"], BYSTANDER], expect_rc=1)
        c.check("03 refuses to end the target's session when the user given is the bystander", "nothing was ended" in out, out[-300:])
        c.check("and the target's FTP client is still connected, the session still listed", ftp_target.alive()
                and len(mine("FTP", TARGET)) == 1)
        out = script("03.sessions_id_DELETE.sh", ["FTP:" + "ab" * 32 + ":999", TARGET], expect_rc=1)
        c.check("03 a session that is not there is not deleted, with the server's reason", "was not found" in out, out[-300:])
        out = script("03.sessions_id_DELETE.sh", ["nosuch:id", TARGET], expect_rc=1)
        c.check("03 an id of the wrong shape is refused", "HTTP 404" in out, out[-300:])

        # 03: end the target's FTP session; only that one goes
        out = script("03.sessions_id_DELETE.sh", [by_protocol["FTP"]["id"], TARGET])
        c.check("03 says whose session it ends and answers 204", "Ending the FTP session of %s..." % TARGET in out and "HTTP 204" in out, out[-300:])
        c.check("the session is gone from the list", harness.wait_until(lambda: not mine("FTP", TARGET)), mine(user=TARGET))
        c.check("the target's FTP client is disconnected", harness.wait_until(lambda: not ftp_target.alive(), 10))
        c.check("the bystander's FTP client is still connected, and its session still listed", ftp_bystander.alive()
                and [s["id"] for s in mine("FTP", BYSTANDER)] == [bystander["id"]])
        c.check("the target's HTTP session is still listed, and its EndUser login still works",
                len(mine("HTTP", TARGET)) == 1 and enduser.status() == 200)
        out = script("03.sessions_id_DELETE.sh", [by_protocol["FTP"]["id"], TARGET], expect_rc=1)
        c.check("03 ending it again: not found", "was not found" in out, out[-300:])
        c.check("ending a session does not lock the account: it logs in again", logins.try_login("FTP", TARGET) == "ok")

        # 05 against the API's own counts, while the sessions are open. The counts are the whole server's: the line is compared
        # with the numbers read just before and just after the example ran, and the counts with how many of our own sessions there are
        before_api = server_counts()
        out = script("05.sessions_statistics_userClass_GET.sh")
        g = server_counts()
        line = "  VirtClass  %d sessions (ftp %d, http %d, ssh %d)"
        c.check("05 prints the VirtClass counts the API reports",
                any(line % (n["total"], n["ftp"], n["http"], n["ssh"]) in out for n in (before_api, g)), (out[-500:], before_api, g))
        own = own_counts()
        grew = {k: g[k] - counts_before[k] for k in g}
        c.check("05 and the counts follow the open sessions: they grew by exactly this check's own, per protocol",
                all(grew[k] == own[k] for k in ("http", "ftp", "ssh")), (g, counts_before, own))
        c.check("05 RealClass is listed too, even with no session", "  RealClass  " in out, out[-500:])
        # 04: empty on this lab (no limit set), whatever it returns it must be readable
        out = script("04.sessions_statistics_bandwidth_GET.sh")
        c.check("04 prints the login name count", "Login names using bandwidth: %d" % len(admin.get("sessions/statistics/bandwidth").json()) in out, out[-300:])
        script("04.sessions_statistics_bandwidth_GET.sh", ["5"])
        script("04.sessions_statistics_bandwidth_GET.sh", ["0"], expect_rc=2)

        # 03: the HTTP session
        out = script("03.sessions_id_DELETE.sh", [by_protocol["HTTP"]["id"], TARGET])
        c.check("03 ends the HTTP session of the target", "Ending the HTTP session of %s..." % TARGET in out and "HTTP 204" in out, out[-300:])
        c.check("the EndUser API answers 401 on the next call", harness.wait_until(lambda: enduser.status() == 401, 10))
        c.check("the bystander's FTP session is still there", ftp_bystander.alive() and len(mine("FTP", BYSTANDER)) == 1)

        # 03: the SSH session
        if ssh is not None:
            c.check("the ssh client is still running before it is ended", ssh.alive())
            out = script("03.sessions_id_DELETE.sh", [by_protocol["SSH"]["id"], TARGET])
            c.check("03 ends the SSH session of the target", "Ending the SSH session of %s..." % TARGET in out and "HTTP 204" in out, out[-300:])
            c.check("the ssh client exits", harness.wait_until(lambda: not ssh.alive(), 10), ssh.alive())
        c.check("none of the target's sessions is left", harness.wait_until(lambda: not mine(user=TARGET)), mine(user=TARGET))
        c.check("the bystander's session was never touched", ftp_bystander.alive() and len(mine("FTP", BYSTANDER)) == 1)
finally:
    for holder in (ftp_target, ftp_bystander, enduser, ssh):
        if holder is not None:
            try:
                holder.close()
            except Exception:
                pass
    logins.cleanup()
    harness.wait_until(lambda: not mine(), 3)   # a closed session can linger in the list for a moment
    # The accounts are ours; ending their sessions first is by id and by user, never anyone else's
    for s in mine():
        admin.delete("sessions/" + s["id"])
    accounts.close()
    # the clean-up of the accounts logs in as them and out again: that session can linger in the list for a moment
    c.check("nothing is left behind: no account, no session of ours",
            not any(admin.exists("accounts/" + a) for a in OURS) and harness.wait_until(lambda: not mine(), 10))
    still = sorted(set(others_before) - {s["id"] for s in sessions()})
    c.check("the sessions open before the check began are still open afterwards (sessions of others that opened since do not count)",
            not still, still)
    admin.logout()

sys.exit(c.done())
