#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Cancels transfers with the real
16.TransferLogs/04.logs_transfers_id_operations_POST.sh example, and shows which can be
cancelled and which cannot, as the server's own isCancelable flag says.

Part A: transfers RUNNING a 10 MB file, kept running about 40 seconds:
  - an upload over FTP, with a throttled client;
  - an upload through the EndUser API, with curl limited to 250 KB a second;
  - a pull over SSH, started through the API, from ST's own SSH server through a
    SlowProxy (tests/integration/lib/dummy_servers.py) that passes 200 KB a second.
For each, once the transfer log shows it In Progress and a few seconds of the file have
gone: the single transfer says "cancelable: no" (03.logs_transfers_id_GET.sh), the cancel is
refused with "is not eligible for cancellation", and the transfer carries on. A running
transfer cannot be cancelled, whatever its size or protocol. The check cuts the client
afterwards.

Part B: a transfer that CAN be cancelled: a PeSIT pull that failed and is waiting to be
retried. Two throwaway accounts with a PeSIT site each, the sender with no file to send,
and a pull by the receiver. The receiver's transfer fails ("File not found" on the sender)
and the server schedules a retry: the pull summary counts it under "to retry" and the
transfer says "cancelable: yes". The example cancels it: HTTP 200 "was successfully
cancelled"; the transfer then says "cancelable: no", the summary counts it as failed, and a
second cancel is refused.

Part A's FTP upload needs the FTP daemon, its pull needs st_callback_host in
integration.conf (this machine's address as the server sees it), and part B needs the
PeSIT daemon. Needs --write and st_allow_writes="yes". Refuses to start when its
example_cx_* objects, or the PeSIT accounts EXCANS and EXCANR, exist, and removes
everything in a finally block, events included. The log entries stay.
"""
import base64
import ftplib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402
import dummy_servers  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the cancel check for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Cancelling a running transfer, with 16.TransferLogs/04.logs_transfers_id_operations_POST.sh")
ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
ACCOUNT, SITE = "example_cx_user", "example_cx_site"
PASSWORD = "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"
ENDUSER_PORT = config.get("st_enduser_port") or str(int(config["st_port"]) - 1)
SSH_HOST = config.get("st_ssh_host") or config["st_server"]
SSH_PORT = int(config.get("st_ssh_port") or 8022)
CALLBACK = config.get("st_callback_host", "")
SIZE = 10 * 1024 * 1024
RATE = 250 * 1024
WORK = tempfile.mkdtemp(prefix="st_cancel_")
# Part B: a PeSIT pair. The names are also PeSIT partner identifiers: short and alphanumeric
SENDER, RECEIVER, PROFILE = "EXCANS", "EXCANR", "EXCANTP"
PESIT_HOST = config.get("st_pesit_host") or config["st_server"]
PESIT_PORT = config.get("st_pesit_port") or "17617"
# A PeSIT site made through the API leaves these empty, and then never connects
PESIT_SITE_DEFAULTS = {"dmz": "none", "pesitId": "", "ptcpConnections": 1, "socketSendReceiveBuffersize": 65536, "receiveMessage": "", "sendMessage": "",
                       "useServerPasswordExpr": False, "usePartnerPasswordExpr": False, "usePreconnectionServerPasswordExpr": False,
                       "usePreconnectionPartnerPasswordExpr": False}


def unique(prefix):
    return "%s_%s.bin" % (prefix, base64.b32encode(os.urandom(3)).decode().lower().rstrip("="))


def entry(name, server_initiated=None):
    rows = admin.get("logs/transfers", params={"account": ACCOUNT, "sortByStartTime": "descending", "limit": 50}).json().get("result", [])
    return next((x for x in rows if x["filename"] == name and (server_initiated is None or bool(x.get("serverInitiated")) == server_initiated)), None)


class Slow(io.RawIOBase):
    """SIZE bytes, 64 KB at a time with a pause, so that the upload lasts."""

    def __init__(self):
        self.sent = 0

    def readable(self):
        return True

    def readinto(self, buffer):
        if self.sent >= SIZE:
            return 0
        time.sleep(0.25)
        n = min(len(buffer), 65536, SIZE - self.sent)
        buffer[:n] = b"x" * n
        self.sent += n
        return n


class FtpUpload:
    def __init__(self, name):
        self.name, self.server_initiated, self.outcome = name, None, None
        self.ftp = ftplib.FTP()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.ftp.connect(config["st_server"], ftp_port, timeout=60)
        self.ftp.login(ACCOUNT, PASSWORD)
        self.thread.start()

    def _run(self):
        try:
            self.ftp.storbinary("STOR " + self.name, Slow(), blocksize=65536)
            self.outcome = "finished"
        except (OSError, EOFError, ftplib.Error) as e:
            self.outcome = "cut short (%s)" % type(e).__name__

    def running(self):
        return self.thread.is_alive()

    def abort(self):
        try:
            self.ftp.sock.close()
        except (OSError, AttributeError):
            pass
        self.thread.join(30)


class HttpUpload:
    def __init__(self, name):
        self.name, self.server_initiated, self.outcome = name, None, None
        self.proc = None

    def start(self):
        url = "https://%s:%s/api/v2.0" % (config["st_server"], ENDUSER_PORT)
        auth = base64.b64encode(("%s:%s" % (ACCOUNT, PASSWORD)).encode()).decode()
        jar, headers = os.path.join(WORK, "jar"), os.path.join(WORK, "headers")
        subprocess.run(["curl", "-s", "-k", "-o", "/dev/null", "-D", headers, "--cookie-jar", jar, "-H", "Authorization: Basic " + auth,
                        "-H", "Referer: THIS_IS_A_RANDOM_TEXT", "-X", "POST", url + "/myself"], check=True)
        csrf = next(l.split(":", 1)[1].strip() for l in open(headers) if l.lower().startswith("csrftoken:"))
        common = ["-H", "Referer: THIS_IS_A_RANDOM_TEXT", "-H", "csrfToken: " + csrf]
        declared = subprocess.run(["curl", "-s", "-k", "-b", jar, "-X", "POST", url + "/fileOperations", "-H", "Content-Type: application/json", *common,
                                   "-d", json.dumps({"operation": "Upload", "filePath": "/" + self.name, "customAttributes": {"transferMode": "BINARY"}})],
                                  capture_output=True, text=True)
        operation = json.loads(declared.stdout)["id"]
        source = os.path.join(WORK, "ten_mb.bin")
        if not os.path.exists(source):
            with open(source, "wb") as f:
                f.write(os.urandom(SIZE))
        self.proc = subprocess.Popen(["curl", "-s", "-k", "-b", jar, "-X", "PUT", url + "/fileOperations/" + operation, "-H", "Content-Type: application/octet-stream",
                                      *common, "--limit-rate", str(RATE), "-w", "HTTP %{http_code}", "--data-binary", "@" + source],
                                     stdout=subprocess.PIPE, text=True)

    def running(self):
        return self.proc.poll() is None

    def abort(self):
        if self.proc.poll() is None:
            self.proc.kill()
        out = self.proc.communicate()[0]
        self.outcome = "finished" if "HTTP 200" in (out or "") else "cut short"


class SlowPull:
    def __init__(self, name):
        self.name, self.server_initiated, self.outcome = name, True, None
        self.proxy = None

    def start(self):
        local = os.path.join(WORK, self.name)
        with open(local, "wb") as f:
            f.write(os.urandom(SIZE))
        with runner.real_credentials(ENDUSER_TREE, dict(config, st_port=ENDUSER_PORT, st_user=ACCOUNT, st_password=PASSWORD)):
            for folder in ("outbound-drop", "incoming"):
                runner.run(os.path.join(ENDUSER_TREE, "02.Files", "02.files_name_POST_folder.sh"), [folder], timeout=60)
            uploaded = runner.run(os.path.join(ENDUSER_TREE, "02.Files", "08.fileOperations_POST_upload.sh"), [local, "outbound-drop"], timeout=180)
        c.check("set up: the 10 MB file is in the account's outbound-drop folder", uploaded.returncode == 0, (uploaded.stdout + uploaded.stderr)[-300:])
        self.proxy = dummy_servers.SlowProxy(SSH_HOST, SSH_PORT, rate=RATE)
        self.proxy.thread.start()
        made = admin.post("sites", {"type": "ssh", "protocol": "ssh", "name": SITE, "account": ACCOUNT, "host": CALLBACK, "port": str(self.proxy.port), "userName": ACCOUNT,
                                    "usePassword": True, "password": PASSWORD, "transferType": "partner", "downloadFolder": "/outbound-drop",
                                    "downloadPatternType": "glob", "downloadPattern": self.name})
        c.check("set up: an SSH site that pulls through the slow proxy", made.status == 201, made.text[:200])
        pulled = admin.post("transfers/operations", {"accountName": ACCOUNT, "site": SITE, "destinationDirectory": "/incoming", "awaitResult": False}, params={"operation": "pull"})
        c.check("set up: the pull is accepted", pulled.status == 202, pulled.text[:200])

    def running(self):
        row = entry(self.name, True)
        return bool(row) and row["status"] == "In Progress"

    def abort(self):
        if self.proxy:
            self.proxy.close()
        found = admin.get("sites", params={"name": SITE, "fields": "id"}).json().get("result") or []
        if found:
            time.sleep(1)
        self.outcome = "cut short"


def running_transfer_is_not_cancelable(label, transfer):
    c.info("--- %s" % label)
    try:
        transfer.start()
    except Exception as e:  # a set up that did not work is a failure of its own
        c.check("%s: the transfer starts" % label, False, repr(e))
        transfer.abort()
        return
    row = None
    for _ in range(30):
        time.sleep(1)
        row = entry(transfer.name, transfer.server_initiated)
        if row:
            break
    c.check("%s: the transfer log shows the 10 MB file In Progress" % label, bool(row) and row["status"] == "In Progress", row and row["status"])
    if not row:
        transfer.abort()
        return
    time.sleep(4)
    ident = row["id"]["urlrepresentation"]
    with runner.real_credentials(ADMIN_TREE, config):
        read = admin_script("03.logs_transfers_id_GET.sh", [ident])
        c.check("%s: the transfer says it is not cancelable" % label, "  cancelable: no, resubmittable: no" in read.stdout, read.stdout[-300:])
        result = admin_script("04.logs_transfers_id_operations_POST.sh", [ident, "cancel"])
    out = result.stdout + result.stderr
    c.check("%s: the cancel is refused: not eligible for cancellation" % label, result.returncode == 1 and "is not eligible for cancellation" in out, out.strip()[-260:])
    time.sleep(3)
    now = entry(transfer.name, transfer.server_initiated)
    c.check("%s: and the transfer carries on, still In Progress and still sending" % label,
            bool(now) and now["status"] == "In Progress" and transfer.running(), now and now["status"])
    transfer.abort()


def admin_script(name, args):
    return runner.run(os.path.join(ADMIN_TREE, "16.TransferLogs", name), args, timeout=120)


def cancel_a_transfer_waiting_for_a_retry():
    c.info("--- a PeSIT pull that failed and is waiting to be retried")
    for name in (SENDER, RECEIVER):
        made = admin.post("accounts", {"name": name, "type": "user", "uid": "1151", "gid": "1151", "homeFolder": "/home/" + name, "transfersWebServiceAllowed": True,
                                       "user": {"name": name, "passwordCredentials": {"password": PASSWORD}}})
        c.check("set up: the account %s" % name, made.status == 201, made.text[:200])
    for owner, partner in ((RECEIVER, SENDER), (SENDER, RECEIVER)):
        made = admin.post("sites", {"type": "pesit", "protocol": "pesit", "name": partner, "account": owner, "host": PESIT_HOST, "port": PESIT_PORT,
                                    "transferType": "unspecified", "storeAndForwardMode": "PRESERVE", **PESIT_SITE_DEFAULTS})
        c.check("set up: %s has a PeSIT site named %s, pointing at this server" % (owner, partner), made.status == 201, made.text[:200])
    for owner, label in ((RECEIVER, "DONT_SEND"), (SENDER, "SEND_FILENAME")):
        made = admin.post("transferProfiles", {"name": PROFILE, "account": owner, "default": True, "sendMapping": "/there_is_no_such_file.txt",
                                               "receiveMapping": "${pesit.fileName}", "fileLabelOption": label, "transferMode": "BINARY",
                                               "recordFormat": "Variable", "recordLength": 2048})
        c.check("set up: %s has a default transfer profile, and the sender has no such file" % owner, made.status == 201, made.text[:200])
    pulled = admin.post("transfers/operations", {"accountName": RECEIVER, "site": SENDER, "destinationDirectory": "/", "transferProfile": PROFILE, "awaitResult": False},
                        params={"operation": "pull"})
    c.check("set up: the PeSIT pull is accepted", pulled.status == 202, pulled.text[:200])
    index = urllib.parse.parse_qs(urllib.parse.urlparse((pulled.json() or {}).get("link", "")).query).get("operationIndex", [""])[0]

    row, one = None, {}
    for _ in range(25):
        time.sleep(2)
        try:
            rows = admin.get("logs/transfers", params={"account": RECEIVER, "sortByStartTime": "descending", "limit": 20}).json().get("result", [])
            row = next((x for x in rows if x.get("serverInitiated") and x["protocol"] == "pesit" and str(x.get("operationIndex")) == index), None)
            if row:
                one = admin.get("logs/transfers/" + row["id"]["urlrepresentation"]).json()
                if one.get("isCancelable"):
                    break
        except st_client.STError:
            continue  # the lab is reached over a VPN that drops now and then
    c.check("the receiving transfer failed, and the server says it is cancelable", bool(row) and row["status"] == "Failed" and one.get("isCancelable") is True,
            (row and row["status"], one.get("isCancelable"), one.get("errorMessage")))
    if not row:
        return
    ident = row["id"]["urlrepresentation"]
    with runner.real_credentials(ADMIN_TREE, config):
        read = admin_script("03.logs_transfers_id_GET.sh", [ident])
        c.check("03 reads it: Failed, cancelable", "  Failed: " in read.stdout and "  cancelable: yes," in read.stdout, read.stdout[-300:])
        summary = admin_script("05.logs_transfers_pullSummary_GET.sh", [index])
        c.check("05 counts it as waiting to be retried: 1 to retry, none failed", "  1 file(s): 0 pulled, 0 failed, 1 to retry, 0 in progress, 0 on hold" in summary.stdout, summary.stdout[-300:])

        cancelled = admin_script("04.logs_transfers_id_operations_POST.sh", [ident, "cancel"])
        out = cancelled.stdout + cancelled.stderr
        c.check("THE CANCEL WORKS: the example exits 0, with HTTP 200, \"was successfully cancelled\"",
                cancelled.returncode == 0 and "HTTP 200" in out and "was successfully cancelled" in out, out.strip()[-260:])

        after = ""
        for _ in range(10):
            after = admin_script("05.logs_transfers_pullSummary_GET.sh", [index]).stdout
            if "0 to retry" in after:
                break
            time.sleep(2)
        c.check("05 now counts it as failed: no more retries", "  1 file(s): 0 pulled, 1 failed, 0 to retry, 0 in progress, 0 on hold" in after, after[-300:])
        read = admin_script("03.logs_transfers_id_GET.sh", [ident])
        c.check("03 says it is no longer cancelable", "  cancelable: no," in read.stdout, read.stdout[-300:])
        again = admin_script("04.logs_transfers_id_operations_POST.sh", [ident, "cancel"])
        c.check("a second cancel is refused: not eligible", again.returncode == 1 and "is not eligible for cancellation" in again.stdout + again.stderr, (again.stdout + again.stderr)[-260:])


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement the transfer log")
    admin.logout()
    sys.exit(c.done())
servers = admin.get("servers").json()
ftp_servers = [s for s in (servers if isinstance(servers, list) else servers.get("result", [])) if s.get("protocol") == "ftp" and s.get("port")]
ftp_port = ftp_servers[0]["port"] if ftp_servers and admin.get("daemons").json().get("ftpStatus") == "Running" else None
pesit_running = admin.get("daemons").json().get("pesitStatus") == "Running"
if any(admin.exists("accounts/" + n) for n in (ACCOUNT, SENDER, RECEIVER)) or (admin.get("sites", params={"name": SITE}).json().get("result")):
    c.check("no %s, %s or %s account, nor %s site, exists yet" % (ACCOUNT, SENDER, RECEIVER, SITE), False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

try:
    made = admin.post("accounts", {"name": ACCOUNT, "type": "user", "uid": "1141", "gid": "1141", "homeFolder": "/home/" + ACCOUNT, "transfersWebServiceAllowed": True,
                                   "user": {"name": ACCOUNT, "passwordCredentials": {"password": PASSWORD}}})
    c.check("set up: a throwaway account", made.status == 201, made.text[:200])
    if ftp_port:
        running_transfer_is_not_cancelable("FTP upload", FtpUpload(unique("cancel_ftp")))
    else:
        c.info("the FTP daemon is not running: the FTP upload is not tried")
    running_transfer_is_not_cancelable("EndUser API upload", HttpUpload(unique("cancel_http")))
    if CALLBACK:
        running_transfer_is_not_cancelable("SSH pull through a slow proxy", SlowPull(unique("cancel_pull")))
    else:
        c.info("st_callback_host is not set: the pull through a slow proxy is not tried")
    if pesit_running:
        cancel_a_transfer_waiting_for_a_retry()
    else:
        c.info("the PeSIT daemon is not running: the transfer waiting for a retry is not tried")
finally:
    time.sleep(2)
    try:
        cleaner = st_client.EndUserClient(config["st_server"], ENDUSER_PORT, ACCOUNT, PASSWORD)
        cleaner.login()
        for folder in ("", "outbound-drop", "incoming"):
            for leftover in cleaner.list_folder(folder) or []:
                cleaner.delete_file((folder + "/" if folder else "") + leftover)
        cleaner.logout()
    except st_client.STError:
        pass
    # A pull is retried: its event would outlive the sites and the accounts
    for _ in range(2):
        for name in (ACCOUNT, SENDER, RECEIVER):
            stuck = [e["id"] for e in admin.get("events", params={"accountName": name, "limit": 100}).json().get("result", [])]
            if stuck:
                admin.post("events/operations", {"ids": stuck}, params={"operation": "delete"})
        time.sleep(2)
    for name in (SENDER, RECEIVER):
        for profile in admin.get("transferProfiles", params={"account": name, "fields": "id"}).json().get("result", []):
            admin.delete("transferProfiles/" + profile["id"])
        for site in admin.get("sites", params={"account": name, "fields": "id"}).json().get("result", []):
            admin.delete("sites/" + site["id"])
    found = admin.get("sites", params={"name": SITE, "fields": "id"}).json().get("result") or []
    if found:
        admin.delete("sites/" + found[0]["id"])
    for name in (ACCOUNT, SENDER, RECEIVER):
        admin.delete("accounts/" + name)
    c.check("nothing is left behind but log entries: no event, account, site or profile",
            not any(admin.get("events", params={"accountName": n}).json().get("result") for n in (ACCOUNT, SENDER, RECEIVER))
            and not any(admin.exists("accounts/" + n) for n in (ACCOUNT, SENDER, RECEIVER))
            and not (admin.get("sites", params={"name": SITE}).json().get("result")))
    admin.logout()

sys.exit(c.done())
