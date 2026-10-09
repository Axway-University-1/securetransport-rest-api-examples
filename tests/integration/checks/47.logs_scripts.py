#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified log examples:
16.TransferLogs 03 to 05, 27.AuditLogs and 28.ServerLogs, in three parts that do
not depend on each other. Each makes something happen, and then finds it in the log.

1. The audit trail. A throwaway business unit, with a name of its own, is created,
   changed and deleted. The examples find its three entries by the exact name, with
   the user and the address the server saw; the CSV export holds them; and an attempt
   to edit an entry's description is answered 204 and changes nothing.

2. The server log, for each protocol: SFTP and HTTP (the EndUser API) are the core ones,
   FTP is the legacy, additional one. A throwaway account (a fresh name and uid on every
   run) logs in, and fails to log in once. The examples find the login and the failure by
   message, component, level and date, read one entry by its id, and export them as CSV.
   What each protocol writes differs, and is asserted as the lab does it (5.5-20260924):
     SFTP  component sshd: INFO "User <name> login success." and INFO (not WARN)
           "User <name> login failed."; tm INFO "User with login name ... over SSH".
     HTTP  component httpd: INFO "User <name> login success." A failed login names NO
           account: INFO "Denying access to unknown user from address <ip>" (also for a
           known account with a wrong password), found by that text, one more than before.
           httpd also WARNs "virtual user <name> does not have email associated" on every
           login: that is no failure.
     FTP   component ftpd: INFO "virtual user <name> logged in from", WARN "Failed login
           for user <name> from".
   FTP is skipped when its daemon is not running; SFTP needs the SSH daemon and an sftp client.

3. The transfer log. A throwaway account uploads a file and pulls it from ST's own SSH
   server: the log then holds the upload, the file served, and the pull. The examples
   read the pull by its id, its summary counts the file (an unknown index counts none),
   and every operation answers what the examples say: resubmit works, while cancel,
   verify, ack and nack are refused for a finished HTTP transfer. Cancelling a transfer
   that is still running is the job of 48.cancel_transfer.py, which fails on the lab these
   were written against, where cancel is refused for a running transfer too.

The logs cannot be cleaned up: the entries of the throwaway objects stay, with names
nobody else uses. The objects themselves are removed in finally blocks.

Needs --write and st_allow_writes="yes".
"""
import base64
import contextlib
import csv
import os
import re
import shutil
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402
import protocol_logins  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the log examples for real")

c = st_client.Checker("Logs, run for real from Admin/API 2.0/bash 16, 27 and 28")
ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
RUN = base64.b32encode(os.urandom(4)).decode().rstrip("=").lower()
PASSWORD = harness.new_password()
ENDUSER_PORT = harness.ports(config).enduser
SSH_HOST = config.get("st_ssh_host") or config["st_server"]
WORK = harness.scratch("st_logs_")


def script(folder, name, args=None, expect_rc=0):
    return harness.run_script(c, ADMIN_TREE, folder + "/" + name, args, expect_rc, timeout=120)


admin = harness.connect(config, c, mock="the bundled mock does not implement the logs")

# ---------------------------------------------------------------- 1. the audit trail
UNIT = "example_log_%s" % RUN
try:
    with runner.real_credentials(ADMIN_TREE, config):
        c.check("an audit entry is made for a business unit created ...", admin.post("businessUnits", {"name": UNIT, "baseFolder": "/home/" + UNIT}).status == 201)
        c.check("... changed ...", admin.patch("businessUnits/" + UNIT, [{"op": "replace", "path": "/homeFolderModifyingAllowed", "value": True}]).status == 204)
        c.check("... and deleted", admin.delete("businessUnits/" + UNIT).status == 204)
        # the audit log is written a moment after the call: wait for the three entries, not a fixed time
        rows = harness.settled(lambda: admin.get("logs/audit", params={"objectName": UNIT, "limit": 20}).json().get("result", []),
                               lambda found: len(found) >= 3, 20, 1) or []
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
# SFTP and HTTP (the EndUser API) are the core protocols, FTP is the legacy, additional one. What each writes to the server log
# differs (measured on 5.5-20260924), and is asserted here as it is:
#   SFTP  component sshd: INFO "User <name> login success." and INFO "User <name> login failed." (a failed login is INFO, not WARN);
#         tm INFO "User with login name "<name>" ... successfully authenticated over SSH"
#   HTTP  component httpd: INFO "User <name> login success."  A failed login names NO account: httpd INFO "Denying access to unknown
#         user from address <ip>" (said even for a known account with a wrong password) and tm INFO "Authentication failed using
#         local."; httpd also WARNs "virtual user <name> does not have email associated" on every login, which is no failure.
#   FTP   component ftpd: INFO "virtual user <name> logged in from", WARN "Failed login for user <name> from"
PORTS = harness.ports(config, admin)
SSH_PORT = PORTS.ssh
DAEMONS = admin.get("daemons").json()
PROTOCOLS = {
    "SFTP": {"component": "SSHD", "token": "sshd", "ok": "User %s login success", "ok_re": r"INFO  sshd  .*User %s login success",
             "fail": "User %s login failed", "fail_re": r"INFO  sshd  .*User %s login failed", "fail_level": "INFO", "fail_names_account": True},
    "HTTP": {"component": "HTTPD", "token": "httpd", "ok": "User %s login success", "ok_re": r"INFO  httpd  .*User %s login success",
             "fail": "Denying access to unknown user from address", "fail_re": r"INFO  httpd  .*Denying access to unknown user from address",
             "fail_level": "INFO", "fail_names_account": False},
    "FTP": {"component": "FTPD", "token": "ftpd", "ok": "virtual user %s logged in", "ok_re": r"INFO  ftpd  .*virtual user %s logged in from",
            "fail": "Failed login for user %s", "fail_re": r"WARN  ftpd  .*Failed login for user %s from", "fail_level": "WARN", "fail_names_account": True},
}
ssh_port = PORTS.ssh if DAEMONS.get("sshStatus") == "Running" else None
ftp_port = PORTS.ftp if DAEMONS.get("ftpStatus") == "Running" else None
logins = protocol_logins.Logins(config["st_server"], ssh_port, ENDUSER_PORT, ftp_port, PASSWORD)
usable = ["SFTP", "HTTP"] + (["FTP"] if ftp_port else [])
if not ssh_port or not shutil.which("sftp"):
    c.check("SFTP, a core protocol, can be exercised", False, "the SSH daemon is not running, or there is no sftp client on this machine")
    usable.remove("SFTP")
if not ftp_port:
    c.info("the FTP daemon is not running: the legacy FTP part of part 2 is left out")
created = []
accounts = contextlib.ExitStack()
try:
    for number, proto in enumerate(usable):
        spec = PROTOCOLS[proto]
        label = proto + (" (legacy)" if proto == "FTP" else "") + ": "
        account = "example_log_%s_%s" % (proto.lower(), RUN)
        comp = spec["component"]
        if proto == "FTP":
            c.info("--- FTP: the legacy protocol, as an additional part")
        created.append(account)
        accounts.enter_context(harness.throwaway_account(admin, c, config, name=account, password=PASSWORD, extra={"transfersWebServiceAllowed": True},
                                                         label=label + "set up: an account to log in as (fresh name and uid)"))
        since_before = time.strftime("%a, %d %b %Y %H:%M:%S GMT", time.gmtime(time.time() - 600))
        failures_before = admin.get("logs/server", params={"fromDate": since_before, "component": comp, "message": spec["fail"] % account if spec["fail_names_account"] else spec["fail"], "limit": 1}).json()["resultSet"]["totalCount"]
        got = logins.try_login(proto, account)
        c.check(label + "the account logs in", got == "ok", got)
        got = logins.try_login(proto, account, "not-the-password")
        c.check(label + "and a wrong password is refused", got.startswith("refused"), got)
        fail_msg = spec["fail"] % account if spec["fail_names_account"] else spec["fail"]
        ok_msg = spec["ok"] % account

        def logged(message):
            return admin.get("logs/server", params={"fromDate": since_before, "component": comp, "message": message, "limit": 1}).json()["resultSet"]["totalCount"]
        # the server log is written a moment after the login: wait until both entries can be found, not a fixed time
        harness.wait_until(lambda: logged(ok_msg) >= 1 and logged(fail_msg) > failures_before, 20, 1)
        with runner.real_credentials(ADMIN_TREE, config):
            out = script("28.ServerLogs", "01.logs_server_GET.sh", ["10", account, comp])
            c.check(label + "28/01 finds the login in the server log, by message, component and date",
                    re.search(spec["ok_re"] % re.escape(account), out) is not None, out[-600:])
            if spec["fail_names_account"]:
                c.check(label + "28/01 and the failed login, as %s, by the account's name" % spec["fail_level"],
                        re.search(spec["fail_re"] % re.escape(account), out) is not None, out[-600:])
            else:
                c.check(label + "28/01 the account's name is not in a failed login's entry: it is not found by it", re.search(spec["fail_re"], out) is None, out[-600:])
                out = script("28.ServerLogs", "01.logs_server_GET.sh", ["10", fail_msg, comp, "INFO"])
                after = admin.get("logs/server", params={"fromDate": since_before, "component": comp, "message": fail_msg, "limit": 1}).json()["resultSet"]["totalCount"]
                c.check(label + "28/01 the failed login is found by its message, an INFO, with no account in it: one more than before",
                        re.search(spec["fail_re"], out) is not None and after == failures_before + 1, (failures_before, after, out[-400:]))
            if spec["fail_names_account"]:
                out = script("28.ServerLogs", "01.logs_server_GET.sh", ["10", fail_msg, comp, spec["fail_level"]])
                part = out.split("The first 20 that match the filters")[-1]
                c.check(label + "28/01 with the level %s the failed login is found, and not the login" % spec["fail_level"],
                        re.search(spec["fail_re"] % re.escape(account), part) is not None and ok_msg not in part, part)
            if spec["fail_level"] == "INFO":
                out = script("28.ServerLogs", "01.logs_server_GET.sh", ["10", account, comp, "WARN"])
                part = out.split("The first 20 that match the filters")[-1]
                c.check(label + "28/01 a failed %s login is NOT a warning: with the level WARN the login and the failure are both missing" % proto,
                        ok_msg not in part and "login failed" not in part, part)
                if proto == "HTTP":
                    c.check(label + "28/01 the only WARN with the account's name is the missing-email notice, which is no failure",
                            "WARN  httpd  " in part and "virtual user %s does not have email associated" % account in part, part)
            out = script("28.ServerLogs", "01.logs_server_GET.sh", ["10", account, comp + ",TM", "INFO,WARN"])
            c.check(label + "28/01 two components and two levels are separate parameters: this component and tm both come back",
                    ("INFO  %s" % spec["token"]) in out and "INFO  tm" in out, out[-600:])
            out = script("28.ServerLogs", "01.logs_server_GET.sh", ["10", account.upper(), comp])
            c.check(label + "28/01 the message is matched with case: the upper case name finds nothing", ok_msg.replace(account, account.upper()) not in out and ok_msg not in out, out[-400:])
            script("28.ServerLogs", "01.logs_server_GET.sh", ["60", "", comp.lower()], expect_rc=2)
            script("28.ServerLogs", "01.logs_server_GET.sh", ["60", "", comp, "loud"], expect_rc=2)

            since = time.strftime("%a, %d %b %Y %H:%M:%S GMT", time.gmtime(time.time() - 600))
            if number == 0:
                everything = admin.get("logs/server", params={"fromDate": since, "component": comp, "limit": 1}).json()["resultSet"]["totalCount"]
                ignored = admin.get("logs/server", params={"fromDate": since, "component": comp, "accountName": "no_such_account_%s" % RUN, "limit": 1}).json()["resultSet"]["totalCount"]
                c.check("the accountName= filter is ignored by the server: any account name answers every entry", everything > 0 and ignored == everything, (everything, ignored))

            found = admin.get("logs/server", params={"fromDate": since, "component": comp, "message": ok_msg, "limit": 5}).json()["result"]
            if found:
                out = script("28.ServerLogs", "02.logs_server_id_GET.sh", [found[0]["id"]["urlrepresentation"]])
                c.check(label + "28/02 reads that entry by its id", "  INFO  %s  thread" % spec["token"] in out and ok_msg in out, out[-500:])
            else:
                c.check(label + "the login entry can be found through the API", False, since)
            script("28.ServerLogs", "02.logs_server_id_GET.sh", ["not-base64"], expect_rc=1)
            if number == 0:
                out = script("28.ServerLogs", "02.logs_server_id_GET.sh")
                c.check("28/02 with no id it reads the newest entry (the log is oldest first)", "  written by " in out, out[-300:])

            target = os.path.join(WORK, "server_%s.csv" % proto.lower())
            script("28.ServerLogs", "03.logs_server_GET_csv.sh", [target, "10", comp])
            with open(target, newline="") as f:
                table = list(csv.reader(f, skipinitialspace=True))
            header = table[0]
            messages = [r[header.index("Message")] for r in table[1:] if len(r) == len(header)]
            c.check(label + "28/03 the CSV has the header and the login, and only %s lines" % comp,
                    header[:5] == ["Time", "Level", "Component", "Thread", "Message"] and any(ok_msg in m for m in messages)
                    and {r[header.index("Component")] for r in table[1:] if len(r) == len(header)} == {comp}, (header[:5], len(messages)))
            if number == 0:
                script("28.ServerLogs", "03.logs_server_GET_csv.sh", [target, "0"], expect_rc=2)
finally:
    logins.cleanup()
    accounts.close()

# ---------------------------------------------------------------- 3. the transfer log
ACCOUNT, SITE = "example_log_tl_" + RUN, "example_log_site"
FILE_NAME = "pull_me_%s.txt" % RUN
if admin.exists("accounts/" + ACCOUNT) or (admin.get("sites", params={"name": SITE}).json().get("result")):
    c.check("no %s account or %s site exists yet" % (ACCOUNT, SITE), False, "remove them first; this check will not touch them")
else:
    site_id = None
    accounts3 = contextlib.ExitStack()
    try:
        accounts3.enter_context(harness.throwaway_account(admin, c, config, name=ACCOUNT, password=PASSWORD, extra={"transfersWebServiceAllowed": True},
                                                          label="set up: the account"))
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
        summary = harness.settled(lambda: admin.get("logs/transfers/pullSummary/" + index).json(),
                                  lambda s: s.get("successful") or s.get("failed"), 40, 2) or {}
        c.check("the file is pulled", summary.get("successful") == 1, summary)

        with runner.real_credentials(ADMIN_TREE, config):
            out = script("16.TransferLogs", "05.logs_transfers_pullSummary_GET.sh", [index])
            c.check("16/05 the summary counts the file: 1 pulled, none failed", "  1 file(s): 1 pulled, 0 failed, 0 to retry, 0 in progress, 0 on hold" in out, out[-300:])
            out = script("16.TransferLogs", "05.logs_transfers_pullSummary_GET.sh", ["no-such-index-%s" % RUN])
            c.check("16/05 an index nobody used is not an error: all counts are 0", "  0 file(s): 0 pulled, 0 failed, 0 to retry, 0 in progress, 0 on hold" in out, out[-300:])
            script("16.TransferLogs", "05.logs_transfers_pullSummary_GET.sh", expect_rc=2)

            # the transfer log is written a little after the transfer ends: wait for the three entries
            entries = harness.settled(
                lambda: [x for x in admin.get("logs/transfers", params={"account": ACCOUNT, "limit": 50, "sortByStartTime": "descending"}).json()["result"]
                         if x["filename"] == FILE_NAME], lambda found: len(found) >= 3, 30, 2) or []
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
        found = admin.get("sites", params={"name": SITE, "fields": "id"}).json().get("result") or []
        if found:
            admin.delete("sites/" + found[0]["id"])
        accounts3.close()   # the files in its home folder, then the account

c.check("nothing is left behind but log entries: no business unit, account or site",
        not admin.exists("businessUnits/" + UNIT) and not any(admin.exists("accounts/" + a) for a in created) and not admin.exists("accounts/" + ACCOUNT)
        and not (admin.get("sites", params={"name": SITE}).json().get("result")))
admin.logout()
sys.exit(c.done())
