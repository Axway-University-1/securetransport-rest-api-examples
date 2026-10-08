#!/usr/bin/env python3
"""
WRITES TO THE SERVER (it ends sessions, of its own throwaway accounts only).
Runs the real, unmodified 32.Sessions examples against live sessions. A session
exists only while a client is connected, so this builds them:

  two end user accounts, example_sess_target and example_sess_bystander;
  the target holds an FTP session (ftplib, idle), an HTTP one (an EndUser API
  login kept open) and an SSH one (the system ssh client, password given by
  SSH_ASKPASS; left out, with a note, when ssh is not there); the bystander
  holds an FTP session too.

It lists them with 01 (by protocol, by user), reads one with 02, and ends them
with 03 one by one, checking each effect on the CLIENT: the idle FTP client
finds the connection closed, the EndUser API answers 401, the ssh process
exits. Every time it checks that the sessions it did not name are still there
(the bystander's FTP session answers, the target's other sessions stay listed),
that 03 refuses when the user given is not the session's owner, and that the
sessions that were open before the check began are the same afterwards. 04 and
05 are read, and the counts of 05 are compared with the list.

Needs --write and st_allow_writes="yes". Refuses to start when either account
exists. It only ever ends a session whose userName is one of its two accounts,
and removes the accounts in a finally block, closing every client first.
"""
import base64
import ftplib
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the sessions examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Sessions, run for real from Admin/API 2.0/bash/32.Sessions")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "32.Sessions")
TARGET, BYSTANDER = "example_sess_target", "example_sess_bystander"
OURS = (TARGET, BYSTANDER)
PASSWORD = "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"
HOST = config["st_server"]
ENDUSER_PORT = config.get("st_enduser_port") or str(int(config["st_port"]) - 1)


def script(name, args=None, expect_rc=0):
    result = runner.run(os.path.join(FOLDER, name), args, timeout=60)
    out = result.stdout + result.stderr
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc, out.strip()[-300:])
    return out


def sessions():
    response = admin.get("sessions")
    return response.json() if response.status == 200 and isinstance(response.json(), list) else []


def mine(protocol=None, user=None):
    return [s for s in sessions() if s["userName"] in OURS and (user is None or s["userName"] == user)
            and (protocol is None or s["protocol"] == protocol)]


def wait_for(predicate, seconds=20):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(1)
    return predicate()


def ftp_alive(client):
    try:
        client.voidcmd("NOOP")
        return True
    except (OSError, EOFError, ftplib.Error):
        return False


def create_account(name, uid):
    return admin.post("accounts", {"name": name, "type": "user", "uid": uid, "gid": uid, "homeFolder": "/home/" + name,
                                   "user": {"name": name, "passwordCredentials": {"password": PASSWORD}}})


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /sessions or the protocol servers")
    admin.logout()
    sys.exit(c.done())
if any(admin.exists("accounts/" + a) for a in OURS):
    c.check("the accounts %s and %s do not exist yet" % OURS, False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

servers = admin.get("servers").json()
servers = servers if isinstance(servers, list) else servers.get("result", [])
ftp_ports = [s["port"] for s in servers if s.get("protocol") == "ftp" and s.get("port")]
ssh_ports = [s["port"] for s in servers if s.get("protocol") == "ssh" and s.get("port")]
daemons = admin.get("daemons").json()
if not ftp_ports or daemons.get("ftpStatus") != "Running":
    c.info("the FTP daemon is not running: this check needs it")
    admin.logout()
    sys.exit(c.done())

work = tempfile.mkdtemp(prefix="sessions_check_")
others_before = sorted(s["id"] for s in sessions())
ftp_target = ftp_bystander = enduser = ssh = None
try:
    for account, uid in ((TARGET, "1081"), (BYSTANDER, "1082")):
        c.check("set up: the account %s" % account, create_account(account, uid).status == 201)

    # Real clients, which stay connected
    ftp_target = ftplib.FTP()
    ftp_target.connect(HOST, ftp_ports[0], timeout=30)
    ftp_target.login(TARGET, PASSWORD)
    ftp_bystander = ftplib.FTP()
    ftp_bystander.connect(HOST, ftp_ports[0], timeout=30)
    ftp_bystander.login(BYSTANDER, PASSWORD)
    enduser = st_client.EndUserClient(HOST, ENDUSER_PORT, TARGET, PASSWORD)
    login = enduser._request("POST", "myself", headers={"Authorization": "Basic " + enduser._auth})
    c.check("set up: the target logs in to the EndUser API and stays logged in", login.status == 200, login.status)
    want = {"FTP": 1, "HTTP": 1}
    if ssh_ports and shutil.which("ssh") and daemons.get("sshStatus") == "Running":
        askpass = os.path.join(work, "askpass.sh")
        with open(askpass, "w") as f:
            f.write("#!/bin/sh\necho '%s'\n" % PASSWORD)
        os.chmod(askpass, stat.S_IRWXU)
        ssh = subprocess.Popen(["ssh", "-p", str(ssh_ports[0]), "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
                                "-o", "PreferredAuthentications=password", "-N", "%s@%s" % (TARGET, HOST)],
                               env=dict(os.environ, SSH_ASKPASS=askpass, SSH_ASKPASS_REQUIRE="force", DISPLAY="x"),
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        want["SSH"] = 1
    else:
        c.info("no ssh client or SSH daemon: the SSH session is left out")

    def counts():
        found = {}
        for s in mine(user=TARGET):
            found[s["protocol"]] = found.get(s["protocol"], 0) + 1
        return found
    c.check("the server lists the target's sessions: %s" % want, wait_for(lambda: counts() == want), counts())
    c.check("and the bystander's FTP session", wait_for(lambda: len(mine("FTP", BYSTANDER)) == 1), mine(user=BYSTANDER))
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
                wait_for(both_complete, 30), both_complete.seen)

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
        c.check("03 with no id, or a malformed one, nothing was ended", wait_for(lambda: len(mine()) == len(want) + 1), len(mine()))
        out = script("03.sessions_id_DELETE.sh", [by_protocol["FTP"]["id"], BYSTANDER], expect_rc=1)
        c.check("03 refuses to end the target's session when the user given is the bystander", "nothing was ended" in out, out[-300:])
        c.check("and the target's FTP client is still connected, the session still listed", ftp_alive(ftp_target)
                and len(mine("FTP", TARGET)) == 1)
        out = script("03.sessions_id_DELETE.sh", ["FTP:" + "ab" * 32 + ":999", TARGET], expect_rc=1)
        c.check("03 a session that is not there is not deleted, with the server's reason", "was not found" in out, out[-300:])
        out = script("03.sessions_id_DELETE.sh", ["nosuch:id", TARGET], expect_rc=1)
        c.check("03 an id of the wrong shape is refused", "HTTP 404" in out, out[-300:])

        # 03: end the target's FTP session; only that one goes
        out = script("03.sessions_id_DELETE.sh", [by_protocol["FTP"]["id"], TARGET])
        c.check("03 says whose session it ends and answers 204", "Ending the FTP session of %s..." % TARGET in out and "HTTP 204" in out, out[-300:])
        c.check("the session is gone from the list", wait_for(lambda: not mine("FTP", TARGET)), mine(user=TARGET))
        c.check("the target's FTP client is disconnected", wait_for(lambda: not ftp_alive(ftp_target), 10))
        c.check("the bystander's FTP client is still connected, and its session still listed", ftp_alive(ftp_bystander)
                and [s["id"] for s in mine("FTP", BYSTANDER)] == [bystander["id"]])
        c.check("the target's HTTP session is still listed, and its EndUser login still works",
                len(mine("HTTP", TARGET)) == 1 and enduser._request("GET", "myself").status == 200)
        out = script("03.sessions_id_DELETE.sh", [by_protocol["FTP"]["id"], TARGET], expect_rc=1)
        c.check("03 ending it again: not found", "was not found" in out, out[-300:])
        relogin = ftplib.FTP()
        relogin.connect(HOST, ftp_ports[0], timeout=30)
        c.check("ending a session does not lock the account: it logs in again", relogin.login(TARGET, PASSWORD).startswith("230"))
        relogin.close()

        # 05 against the list, while the sessions are open
        counts_now = {}
        for s in sessions():
            if s["userClass"] == "VirtClass":
                counts_now[s["protocol"]] = counts_now.get(s["protocol"], 0) + 1
        api = {k["userClass"]: k for k in admin.get("sessions/statistics/userClass").json()}
        out = script("05.sessions_statistics_userClass_GET.sh")
        g = api["VirtClass"]["globalLoggedInCounters"]
        c.check("05 prints the VirtClass counts the API reports",
                "  VirtClass  %d sessions (ftp %d, http %d, ssh %d)" % (g["total"], g["ftp"], g["http"], g["ssh"]) in out, out[-500:])
        c.check("05 and the counts follow the open sessions", g["http"] == counts_now.get("HTTP", 0) and g["ftp"] == counts_now.get("FTP", 0)
                and g["ssh"] == counts_now.get("SSH", 0), (g, counts_now))
        c.check("05 RealClass is listed too, even with no session", "  RealClass  " in out, out[-500:])
        # 04: empty on this lab (no limit set), whatever it returns it must be readable
        out = script("04.sessions_statistics_bandwidth_GET.sh")
        c.check("04 prints the login name count", "Login names using bandwidth: %d" % len(admin.get("sessions/statistics/bandwidth").json()) in out, out[-300:])
        script("04.sessions_statistics_bandwidth_GET.sh", ["5"])
        script("04.sessions_statistics_bandwidth_GET.sh", ["0"], expect_rc=2)

        # 03: the HTTP session
        out = script("03.sessions_id_DELETE.sh", [by_protocol["HTTP"]["id"], TARGET])
        c.check("03 ends the HTTP session of the target", "Ending the HTTP session of %s..." % TARGET in out and "HTTP 204" in out, out[-300:])
        c.check("the EndUser API answers 401 on the next call", wait_for(lambda: enduser._request("GET", "myself").status == 401, 10))
        c.check("the bystander's FTP session is still there", ftp_alive(ftp_bystander) and len(mine("FTP", BYSTANDER)) == 1)

        # 03: the SSH session
        if ssh is not None:
            c.check("the ssh client is still running before it is ended", ssh.poll() is None)
            out = script("03.sessions_id_DELETE.sh", [by_protocol["SSH"]["id"], TARGET])
            c.check("03 ends the SSH session of the target", "Ending the SSH session of %s..." % TARGET in out and "HTTP 204" in out, out[-300:])
            c.check("the ssh client exits", wait_for(lambda: ssh.poll() is not None, 10), ssh.poll())
        c.check("none of the target's sessions is left", wait_for(lambda: not mine(user=TARGET)), mine(user=TARGET))
        c.check("the bystander's session was never touched", ftp_alive(ftp_bystander) and len(mine("FTP", BYSTANDER)) == 1)
finally:
    for client in (ftp_target, ftp_bystander):
        try:
            client.close()
        except Exception:
            pass
    if ssh is not None and ssh.poll() is None:
        ssh.terminate()
    if enduser is not None:
        try:
            enduser.logout()
        except Exception:
            pass
    time.sleep(1)
    # The accounts are ours; ending their sessions first is by id and by user, never anyone else's
    for s in mine():
        admin.delete("sessions/" + s["id"])
    for account in OURS:
        admin.delete("accounts/" + account)
    shutil.rmtree(work, ignore_errors=True)
    c.check("nothing is left behind: no account, no session of ours", not any(admin.exists("accounts/" + a) for a in OURS) and not mine())
    c.check("the sessions open before the check began are the same afterwards", sorted(s["id"] for s in sessions()) == others_before,
            (others_before, [s["id"] for s in sessions()]))
    admin.logout()

sys.exit(c.done())
