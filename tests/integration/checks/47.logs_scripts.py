#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified log examples:
16.TransferLogs 03 to 05, 27.AuditLogs and 28.ServerLogs, in three parts that do
not depend on each other. Each makes something happen, and then finds it in the log.

1. The audit trail. A throwaway business unit, with a name of its own, is created,
   changed and deleted. The examples find its three entries by the exact name, with
   the user and the address the server saw; the CSV export holds them; and an attempt
   to edit an entry's description is answered 204 and changes nothing.

2. The server log. A throwaway account logs in over FTP, and fails to log in once. The
   examples find the "logged in" entry and the "Failed login" warning by message,
   component, level and date, read one entry by its id, and export them as CSV.
   Skipped when the FTP daemon is not running.

3. The transfer log. A throwaway account uploads a file and pulls it from ST's own SSH
   server: the log then holds the upload, the file served, and the pull. The examples
   read the pull by its id, its summary counts the file (an unknown index counts none),
   and every operation answers what the examples say: resubmit works, while cancel,
   verify, ack and nack are refused for a finished HTTP transfer. Cancelling a transfer
   that is still running is the job of 48.cancel_transfer.py, which fails on the lab these
   were written against, where cancel is refused for a running transfer too.

The logs cannot be cleaned up: the entries of the throwaway objects stay, with names
nobody else uses. The objects themselves are removed in finally blocks.

Needs --write and st_allow_writes="yes". The FTP part needs the daemon running.
"""
import base64
import csv
import ftplib
import io
import os
import re
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
    st_client.skip("read only run, pass --write to run the log examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Logs, run for real from Admin/API 2.0/bash 16, 27 and 28")
ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
RUN = base64.b32encode(os.urandom(4)).decode().rstrip("=").lower()
PASSWORD = "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"
ENDUSER_PORT = config.get("st_enduser_port") or str(int(config["st_port"]) - 1)
SSH_HOST = config.get("st_ssh_host") or config["st_server"]
SSH_PORT = config.get("st_ssh_port") or "8022"
WORK = tempfile.mkdtemp(prefix="st_logs_")


def script(folder, name, args=None, expect_rc=0):
    result = runner.run(os.path.join(ADMIN_TREE, folder, name), args, timeout=120)
    out = result.stdout + result.stderr
    c.check("%s/%s %s exits %s" % (folder, name, " ".join(args or []), expect_rc), result.returncode == expect_rc, out.strip()[-300:])
    return out


def account_body(name, uid):
    return {"name": name, "type": "user", "uid": uid, "gid": uid, "homeFolder": "/home/" + name, "transfersWebServiceAllowed": True,
            "user": {"name": name, "passwordCredentials": {"password": PASSWORD}}}


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement the logs")
    admin.logout()
    sys.exit(c.done())

# ---------------------------------------------------------------- 1. the audit trail
UNIT = "example_log_%s" % RUN
try:
    with runner.real_credentials(ADMIN_TREE, config):
        c.check("an audit entry is made for a business unit created ...", admin.post("businessUnits", {"name": UNIT, "baseFolder": "/home/" + UNIT}).status == 201)
        c.check("... changed ...", admin.patch("businessUnits/" + UNIT, [{"op": "replace", "path": "/homeFolderModifyingAllowed", "value": True}]).status == 204)
        c.check("... and deleted", admin.delete("businessUnits/" + UNIT).status == 204)
        time.sleep(2)
        rows = admin.get("logs/audit", params={"objectName": UNIT, "limit": 20}).json().get("result", [])
        by_operation = {r["operationType"]: r for r in rows}
        c.check("the audit log holds exactly one CREATE, one UPDATE and one DELETE for it", sorted(by_operation) == ["CREATE", "DELETE", "UPDATE"] and len(rows) == 3, [r["operationType"] for r in rows])
        c.check("each says who: the administrator the examples log in as, and the address the server saw",
                all(r["userName"] == config["st_user"] and r.get("remoteAddress") for r in rows), [(r["userName"], r.get("remoteAddress")) for r in rows])
        if config.get("st_callback_host"):
            c.check("and that address is this machine's", all(r["remoteAddress"] == config["st_callback_host"] for r in rows), [r["remoteAddress"] for r in rows])
        c.check("objectName= is matched exactly, with case: the upper case name finds nothing",
                admin.get("logs/audit", params={"objectName": UNIT.upper(), "limit": 1}).json()["resultSet"]["totalCount"] == 0)
        c.check("objectType=businessunit finds nothing either: the type is exact too",
                admin.get("logs/audit", params={"objectType": "businessunit", "objectName": UNIT, "limit": 1}).json()["resultSet"]["totalCount"] == 0)

        out = script("27.AuditLogs", "01.logs_audit_GET.sh", ["1", "BusinessUnit", UNIT])
        part = out.split("The latest 10 entries for those filters:")[-1]
        c.check("27/01 lists the three entries for that type and name, newest first",
                [l.split()[6] for l in part.strip().split("\n") if l.strip()] == ["DELETE", "UPDATE", "CREATE"]
                and all((" by %s from " % config["st_user"]) in l for l in part.strip().split("\n")), part)
        out = script("27.AuditLogs", "01.logs_audit_GET.sh", ["1", "BusinessUnit", UNIT, "CREATE"])
        part = out.split("The latest 10 entries for those filters:")[-1]
        c.check("27/01 and only the CREATE one when asked", len([l for l in part.strip().split("\n") if l.strip()]) == 1 and "  CREATE  " in part, part)
        script("27.AuditLogs", "01.logs_audit_GET.sh", ["1", "", "", "EXPLODE"], expect_rc=2)
        script("27.AuditLogs", "01.logs_audit_GET.sh", ["0"], expect_rc=2)

        entry = by_operation.get("CREATE")
        out = script("27.AuditLogs", "02.logs_audit_id_GET.sh", [entry["id"]])
        c.check("27/02 reads the CREATE entry", ("  CREATE BusinessUnit %s," % UNIT) in out and ("  by %s from " % config["st_user"]) in out, out[-400:])
        script("27.AuditLogs", "02.logs_audit_id_GET.sh", ["nope"], expect_rc=1)
        script("27.AuditLogs", "02.logs_audit_id_GET.sh")

        before = admin.get("logs/audit/" + entry["id"]).json()["description"]
        out = script("27.AuditLogs", "03.logs_audit_id_PUT.sh", [entry["id"], "rewritten by the check"])
        after = admin.get("logs/audit/" + entry["id"]).json()["description"]
        c.check("27/03 an edit of an audit entry is answered 204 ...", "HTTP 204" in out, out[-300:])
        c.check("... and changes nothing: the audit trail cannot be edited", after == before and after != "rewritten by the check", (before, after))
        c.check("27/03 says so", "It did not change: the audit log cannot be edited." in out, out[-300:])
        script("27.AuditLogs", "03.logs_audit_id_PUT.sh", expect_rc=2)
        script("27.AuditLogs", "03.logs_audit_id_PUT.sh", ["nope"], expect_rc=1)

        target = os.path.join(WORK, "audit.csv")
        out = script("27.AuditLogs", "04.logs_audit_GET_csv.sh", [target, "1"])
        with open(target, newline="") as f:
            table = list(csv.reader(f, skipinitialspace=True))
        header = table[0]
        mine = [r for r in table[1:] if len(r) == len(header) and r[header.index("Object Name")] == UNIT]
        c.check("27/04 the CSV has the header and the three entries of the unit",
                header[:4] == ["User Name", "Remote Host", "User Agent", "Date Modified"] and sorted(r[header.index("Operation Type")] for r in mine) == ["CREATE", "DELETE", "UPDATE"],
                (header[:4], len(mine)))
        script("27.AuditLogs", "04.logs_audit_GET_csv.sh", [target, "0"], expect_rc=2)
finally:
    admin.delete("businessUnits/" + UNIT)

# ---------------------------------------------------------------- 2. the server log
FTP_ACCOUNT = "example_log_ftp"
servers = admin.get("servers").json()
ftp_servers = [s for s in (servers if isinstance(servers, list) else servers.get("result", [])) if s.get("protocol") == "ftp" and s.get("port")]
ftp_port = ftp_servers[0]["port"] if ftp_servers and admin.get("daemons").json().get("ftpStatus") == "Running" else None
if not ftp_port:
    c.info("the FTP daemon is not running: part 2, the server log, is skipped")
elif admin.exists("accounts/" + FTP_ACCOUNT):
    c.check("no %s account exists yet" % FTP_ACCOUNT, False, "remove it first; this check will not touch it")
else:
    try:
        c.check("set up: an account to log in as", admin.post("accounts", account_body(FTP_ACCOUNT, "1131")).status == 201)
        ftp = ftplib.FTP()
        ftp.connect(config["st_server"], ftp_port, timeout=15)
        ftp.login(FTP_ACCOUNT, PASSWORD)
        ftp.quit()
        refused = False
        try:
            ftp = ftplib.FTP()
            ftp.connect(config["st_server"], ftp_port, timeout=15)
            ftp.login(FTP_ACCOUNT, "not-the-password")
        except ftplib.error_perm:
            refused = True
        c.check("the account logs in over FTP, and a wrong password is refused", refused)
        time.sleep(3)
        with runner.real_credentials(ADMIN_TREE, config):
            out = script("28.ServerLogs", "01.logs_server_GET.sh", ["10", FTP_ACCOUNT, "FTPD"])
            c.check("28/01 finds the login in the server log, by message, component and date",
                    re.search(r"INFO  ftpd  .*virtual user %s logged in from" % FTP_ACCOUNT, out) is not None, out[-600:])
            c.check("28/01 and the failed one as a warning", re.search(r"WARN  ftpd  .*Failed login for user %s from" % FTP_ACCOUNT, out) is not None, out[-600:])
            out = script("28.ServerLogs", "01.logs_server_GET.sh", ["10", FTP_ACCOUNT, "FTPD", "WARN"])
            part = out.split("The first 20 that match the filters")[-1]
            c.check("28/01 with the level WARN only the failed login is left",
                    "Failed login for user %s" % FTP_ACCOUNT in part and "logged in from" not in part, part)
            out = script("28.ServerLogs", "01.logs_server_GET.sh", ["10", FTP_ACCOUNT, "FTPD,HTTPD", "INFO,WARN"])
            c.check("28/01 two components and two levels are separate parameters, and both levels come back",
                    "INFO  ftpd" in out and "WARN  ftpd" in out, out[-600:])
            out = script("28.ServerLogs", "01.logs_server_GET.sh", ["10", FTP_ACCOUNT.upper(), "FTPD"])
            c.check("28/01 the message is matched with case: the upper case name finds nothing", "logged in from" not in out, out[-400:])
            script("28.ServerLogs", "01.logs_server_GET.sh", ["60", "", "ftpd"], expect_rc=2)
            script("28.ServerLogs", "01.logs_server_GET.sh", ["60", "", "FTPD", "loud"], expect_rc=2)

            since = time.strftime("%a, %d %b %Y %H:%M:%S GMT", time.gmtime(time.time() - 600))
            everything = admin.get("logs/server", params={"fromDate": since, "component": "FTPD", "limit": 1}).json()["resultSet"]["totalCount"]
            ignored = admin.get("logs/server", params={"fromDate": since, "component": "FTPD", "accountName": "no_such_account_%s" % RUN, "limit": 1}).json()["resultSet"]["totalCount"]
            c.check("the accountName= filter is ignored by the server: any account name answers every entry", everything > 0 and ignored == everything, (everything, ignored))

            found = admin.get("logs/server", params={"fromDate": since, "component": "FTPD", "message": "virtual user %s logged in" % FTP_ACCOUNT, "limit": 5}).json()["result"]
            if found:
                out = script("28.ServerLogs", "02.logs_server_id_GET.sh", [found[0]["id"]["urlrepresentation"]])
                c.check("28/02 reads that entry by its id", "  INFO  ftpd  thread" in out and "virtual user %s logged in" % FTP_ACCOUNT in out, out[-500:])
            else:
                c.check("the login entry can be found through the API", False, since)
            script("28.ServerLogs", "02.logs_server_id_GET.sh", ["not-base64"], expect_rc=1)
            out = script("28.ServerLogs", "02.logs_server_id_GET.sh")
            c.check("28/02 with no id it reads the newest entry (the log is oldest first)", "  written by " in out, out[-300:])

            target = os.path.join(WORK, "server.csv")
            script("28.ServerLogs", "03.logs_server_GET_csv.sh", [target, "10", "FTPD"])
            with open(target, newline="") as f:
                table = list(csv.reader(f, skipinitialspace=True))
            header = table[0]
            messages = [r[header.index("Message")] for r in table[1:] if len(r) == len(header)]
            c.check("28/03 the CSV has the header and the login, and only FTPD lines",
                    header[:5] == ["Time", "Level", "Component", "Thread", "Message"] and any("virtual user %s logged in" % FTP_ACCOUNT in m for m in messages)
                    and {r[header.index("Component")] for r in table[1:] if len(r) == len(header)} == {"FTPD"}, (header[:5], len(messages)))
            script("28.ServerLogs", "03.logs_server_GET_csv.sh", [target, "0"], expect_rc=2)
    finally:
        admin.delete("accounts/" + FTP_ACCOUNT)

# ---------------------------------------------------------------- 3. the transfer log
ACCOUNT, SITE = "example_log_tl", "example_log_site"
FILE_NAME = "pull_me_%s.txt" % RUN
if admin.exists("accounts/" + ACCOUNT) or (admin.get("sites", params={"name": SITE}).json().get("result")):
    c.check("no %s account or %s site exists yet" % (ACCOUNT, SITE), False, "remove them first; this check will not touch them")
else:
    site_id = None
    try:
        c.check("set up: the account", admin.post("accounts", account_body(ACCOUNT, "1132")).status == 201)
        local = os.path.join(WORK, FILE_NAME)
        with open(local, "w") as f:
            f.write("a file for the partner to serve\n")
        with runner.real_credentials(ENDUSER_TREE, dict(config, st_port=ENDUSER_PORT, st_user=ACCOUNT, st_password=PASSWORD)):
            for folder in ("outbound-drop", "incoming"):
                runner.run(os.path.join(ENDUSER_TREE, "02.Files", "02.files_name_POST_folder.sh"), [folder], timeout=60)
            upload = runner.run(os.path.join(ENDUSER_TREE, "02.Files", "08.fileOperations_POST_upload.sh"), [local, "outbound-drop"], timeout=90)
            c.check("set up: a file uploaded for the pull", upload.returncode == 0, (upload.stdout + upload.stderr)[-300:])
        made = admin.post("sites", {"type": "ssh", "protocol": "ssh", "name": SITE, "account": ACCOUNT, "host": SSH_HOST, "port": SSH_PORT, "userName": ACCOUNT,
                                    "usePassword": True, "password": PASSWORD, "transferType": "partner", "downloadFolder": "/outbound-drop",
                                    "downloadPatternType": "glob", "downloadPattern": "*.txt"})
        c.check("set up: an SSH site that pulls from ST's own SSH server", made.status == 201, made.text[:200])
        pulled = admin.post("transfers/operations", {"accountName": ACCOUNT, "site": SITE, "destinationDirectory": "/incoming", "awaitResult": False}, params={"operation": "pull"})
        match = re.search(r"operationIndex=([0-9a-f-]+)", pulled.text)
        c.check("the pull is accepted (202), and its link carries the operation index", pulled.status == 202 and match is not None, pulled.text[:200])
        index = match.group(1) if match else "none"
        summary = {}
        for _ in range(20):
            summary = admin.get("logs/transfers/pullSummary/" + index).json()
            if summary.get("successful") or summary.get("failed"):
                break
            time.sleep(2)
        c.check("the file is pulled", summary.get("successful") == 1, summary)

        with runner.real_credentials(ADMIN_TREE, config):
            out = script("16.TransferLogs", "05.logs_transfers_pullSummary_GET.sh", [index])
            c.check("16/05 the summary counts the file: 1 pulled, none failed", "  1 file(s): 1 pulled, 0 failed, 0 to retry, 0 in progress, 0 on hold" in out, out[-300:])
            out = script("16.TransferLogs", "05.logs_transfers_pullSummary_GET.sh", ["no-such-index-%s" % RUN])
            c.check("16/05 an index nobody used is not an error: all counts are 0", "  0 file(s): 0 pulled, 0 failed, 0 to retry, 0 in progress, 0 on hold" in out, out[-300:])
            script("16.TransferLogs", "05.logs_transfers_pullSummary_GET.sh", expect_rc=2)

            entries = [x for x in admin.get("logs/transfers", params={"account": ACCOUNT, "limit": 50}).json()["result"] if x["filename"] == FILE_NAME]
            pull = next((x for x in entries if x.get("serverInitiated")), None)
            upload_entry = next((x for x in entries if x["protocol"] == "http"), None)
            c.check("the log holds the upload, the file served over SSH, and the pull; only the pull carries the operation index",
                    len(entries) == 3 and pull and pull.get("operationIndex") == index and all(x.get("operationIndex") != index for x in entries if x is not pull),
                    [(x["protocol"], x["incoming"], x.get("operationIndex")) for x in entries])
            if pull and upload_entry:
                out = script("16.TransferLogs", "03.logs_transfers_id_GET.sh", [pull["id"]["urlrepresentation"]])
                c.check("16/03 reads the pull by its id: Processed, the file, the account", "  Processed: %s (" % FILE_NAME in out and ("account %s," % ACCOUNT) in out, out[-400:])
                script("16.TransferLogs", "03.logs_transfers_id_GET.sh", ["not-base64!"], expect_rc=1)
                out = script("16.TransferLogs", "03.logs_transfers_id_GET.sh")
                c.check("16/03 with no id it reads the newest transfer", "  started " in out, out[-300:])

                ident = upload_entry["id"]["urlrepresentation"]
                out = script("16.TransferLogs", "04.logs_transfers_id_operations_POST.sh", [ident, "cancel"], expect_rc=1)
                c.check("16/04 cancel of a finished transfer is refused: not eligible", "is not eligible for cancellation" in out, out[-300:])
                out = script("16.TransferLogs", "04.logs_transfers_id_operations_POST.sh", [ident, "verify"], expect_rc=1)
                c.check("16/04 verify: the transfer has no receipt", "does not have a receipts" in out, out[-300:])
                for operation in ("ack", "nack"):
                    out = script("16.TransferLogs", "04.logs_transfers_id_operations_POST.sh", [ident, operation, "from the check"], expect_rc=1)
                    c.check("16/04 %s: HTTP does not support acknowledgements" % operation, "protocol http does not support acknowledgements" in out, out[-300:])
                out = script("16.TransferLogs", "04.logs_transfers_id_operations_POST.sh", [ident, "resubmit"])
                c.check("16/04 resubmit works on a finished transfer", "was successfully resubmitted" in out and "HTTP 200" in out, out[-300:])
                script("16.TransferLogs", "04.logs_transfers_id_operations_POST.sh", [ident], expect_rc=2)
                script("16.TransferLogs", "04.logs_transfers_id_operations_POST.sh", [ident, "explode"], expect_rc=2)
            else:
                c.check("the upload and the pull can be found in the log", False, [(x["protocol"], x["incoming"]) for x in entries])
    finally:
        try:
            cleaner = st_client.EndUserClient(config["st_server"], ENDUSER_PORT, ACCOUNT, PASSWORD)
            cleaner.login()
            for folder in ("outbound-drop", "incoming"):
                for leftover in cleaner.list_folder(folder) or []:
                    cleaner.delete_file("%s/%s" % (folder, leftover))
            cleaner.logout()
        except st_client.STError:
            pass
        found = admin.get("sites", params={"name": SITE, "fields": "id"}).json().get("result") or []
        if found:
            admin.delete("sites/" + found[0]["id"])
        admin.delete("accounts/" + ACCOUNT)

c.check("nothing is left behind but log entries: no business unit, account or site",
        not admin.exists("businessUnits/" + UNIT) and not admin.exists("accounts/" + FTP_ACCOUNT) and not admin.exists("accounts/" + ACCOUNT)
        and not (admin.get("sites", params={"name": SITE}).json().get("result")))
admin.logout()
sys.exit(c.done())
