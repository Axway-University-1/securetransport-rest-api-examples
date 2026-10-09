#!/usr/bin/env python3
"""
WRITES TO THE SERVER. A PeSIT loop between two throwaway accounts on this one
server, and the real, unmodified 90.EndToEndAcknowledgment scripts run on the
transfers it makes - the ACK branch as well as the NACK branch, and
IteratePesitInbounds.sh.

The loop copies the shape of a working PeSIT pair (confirmed directly on a lab
server): each account has a PeSIT site named after the OTHER account, pointing
at this server's own PeSIT port, and a default transfer profile. The receiver
pulls from the site named after the sender; the sender's profile hands over the
one file this check put in its home folder, and the receiver's profile lands
it, in the folder the pull names, as ${pesit.fileName} - the profile's name.

Three things found while building it, each confirmed directly:
  - A PeSIT site created through the API leaves ten fields empty that a site
    made in the admin UI fills in (dmz, pesitId, ptcpConnections, ...). With
    them empty the pull is accepted and never connects. They are set here.
  - sendMapping "/*" is not a wildcard: the sender looks for a file named "*"
    and answers "File not found". The mapping names the file instead.
  - A relative receiveMapping lands the file in the pull's
    destinationDirectory. (An absolute one was once recorded here as landing in
    the home folder; check 58 did not see that: the server stores a leading /
    on every receiveMapping and "/abs.txt" landed in the destinationDirectory.)
  - Deleting a received file through the End User API is logged as an
    outgoing transfer under the file's coreId. Acknowledgment.sh counts it as
    the outbound, and ACKs. So nothing here deletes a received file before it
    is acknowledged. An ACK sent after the account is deleted is answered 200
    and not recorded.

  ZZTESTPS   the sender: one file in its home folder
  ZZTESTPR   the receiver: pulls it over PeSIT, three ways

(the prefix without its punctuation: a PeSIT partner identifier is short and
alphanumeric, and the account names are the identifiers)

  1. NACK  pulled into /nack, where nothing forwards it. Acknowledgment.sh
           finds no outbound transfer with its coreId and sends a NACK.
  2. ACK   pulled into /ack, which a subscription and a composite route watch:
           the route pushes the file on over SSH, to the sender's /returned
           folder, under the same coreId. Acknowledgment.sh finds that outbound
           transfer and sends an ACK.
  3. Iterate  one more of each. IteratePesitInbounds.sh must ACK the forwarded
           one and leave the other unacknowledged, for a later run - it calls
           Acknowledgment.sh without NACKs. Run from another folder, which is
           how its relative call to Acknowledgment.sh was found broken.

IteratePesitInbounds.sh acts on every unacknowledged PeSIT inbound transfer on
the server in its time window, not only this check's. So it only runs when
every such transfer in the last hour belongs to an account carrying this
check's prefix (this run's, or a throwaway of an earlier one); otherwise that
part is skipped, and says so. Whatever this check leaves unacknowledged
is NACKed at the end, so a later run of the script by anyone finds nothing of
it.

Everything is created under st_object_prefix and removed in a finally block.

Needs --write and st_allow_writes="yes". Optional in integration.conf:
st_pesit_host and st_pesit_port (this server's PeSIT listener, default
st_server and 17617), st_ssh_host, st_ssh_port, st_enduser_port and
st_chain_wait_seconds, as for 31.
"""
import datetime
import email.utils
import os
import re
import subprocess
import sys
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run a PeSIT loop and the acknowledgment scripts for real")

c = st_client.Checker("PeSIT loop between two throwaway accounts, and the scripts in "
                      "Admin/API 2.0/bash/90.EndToEndAcknowledgment, run for real")

PREFIX = config.get("st_object_prefix") or "ZZTEST_"
# The two accounts' names are also their PeSIT partner identifiers, which are
# short and alphanumeric: the prefix without its punctuation, plus PS or PR
PESIT_PREFIX = re.sub(r"[^A-Za-z0-9]", "", PREFIX)[:6]
SENDER = PESIT_PREFIX + "PS"
RECEIVER = PESIT_PREFIX + "PR"
PASSWORD = harness.new_password()
PROFILE = PESIT_PREFIX + "TP"   # also the PeSIT file name, so alphanumeric too
APPLICATION = PREFIX + "PesitApplication"
TEMPLATE = PREFIX + "PesitTemplate"
SIMPLE = PREFIX + "PesitForward"
COMPOSITE = PREFIX + "PesitComposite"
RETURN_SITE = PREFIX + "PesitReturn"
SENT_FILE = "pesit_loop.txt"
SENT_CONTENT = b"A file sent over PeSIT between two throwaway accounts.\n"

PESIT_HOST = config.get("st_pesit_host") or config["st_server"]
SSH_HOST = config.get("st_ssh_host") or config["st_server"]
ENDUSER_PORT = harness.ports(config).enduser
WAIT = int(config.get("st_chain_wait_seconds") or "90")

wait_until = lambda predicate, timeout=WAIT, interval=3: harness.wait_until(predicate, timeout, interval)  # noqa: E731

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
ACK_DIR = os.path.join(BASH_TREE, "90.EndToEndAcknowledgment")

client = harness.connect(config, c, mock=("the bundled mock does not implement PeSIT, /transfers or /logs/transfers; "
                                          "run this against a real server to exercise it"))
PORTS = harness.ports(config, client)
PESIT_PORT, SSH_PORT = PORTS.pesit, PORTS.ssh


# Set explicitly: a PeSIT site created through the API, unlike one created in
# the admin UI, otherwise leaves these empty, and the transfer never connects
# (confirmed directly, comparing with a working site field by field)
PESIT_SITE_DEFAULTS = {
    "dmz": "none", "pesitId": "", "ptcpConnections": 1, "socketSendReceiveBuffersize": 65536,
    "receiveMessage": "", "sendMessage": "", "useServerPasswordExpr": False, "usePartnerPasswordExpr": False,
    "usePreconnectionServerPasswordExpr": False, "usePreconnectionPartnerPasswordExpr": False,
}


def results(path, params=None):
    return (client.get(path, params=params).json() or {}).get("result", [])


def created(label, response):
    ok = response.status in (200, 201, 204)
    c.check(label, ok, "HTTP %s %s" % (response.status, response.text[:300]))
    if not ok:
        raise SystemExit
    return response


def route_id(name):
    return next((r.get("id") for r in results("routes", {"name": name})), None)


def pull(folder):
    """A PeSIT pull into the receiver's folder. The coreId of the inbound transfer."""
    response = client.post("transfers/operations",
                           {"accountName": RECEIVER, "site": SENDER, "destinationDirectory": folder,
                            "transferProfile": PROFILE, "awaitResult": False},
                           params={"operation": "pull"})
    c.check("a PeSIT pull into %s is accepted" % folder, response.status == 202, response.text[:300])
    link = (response.json() or {}).get("link", "")
    index = urllib.parse.parse_qs(urllib.parse.urlparse(link).query).get("operationIndex", [None])[0]
    entry = wait_until(lambda: next(
        (e for e in (client.get("logs/transfers", params={"operationIndex": index}).json() or {})
         .get("pullEntries", []) if e.get("status") in ("Processed", "Failed")), None)) if index else None
    if entry and entry.get("status") != "Processed":
        detail = client.get(entry["metadata"]["links"]["self"].split("/api/v2.0/", 1)[1]).json() or {}
        c.check("the pull into %s succeeded" % folder, False, detail.get("errorMessage"))
        raise SystemExit
    c.check("the pull into %s arrived as a processed PeSIT transfer, with a coreId" % folder,
            bool(entry and entry.get("coreId")), entry or link)
    if not entry or not entry.get("coreId"):
        raise SystemExit
    c.info("%s: coreId %s, landed as %s" % (folder, entry["coreId"], entry.get("localFilename")))
    return entry["coreId"]


def outbound_processed(core_id):
    return ((client.get("logs/transfers", params={"direction": "Outgoing", "status": "Processed",
                                                   "coreId": core_id}).json() or {})
            .get("resultSet", {}).get("returnCount") or 0) > 0


def ack_status(core_id):
    statuses = [e.get("pesitAckStatus") for e in results("logs/transfers", {"coreId": core_id})
                if e.get("pesitAckStatus")]
    return statuses[0] if statuses else None


def acknowledge(core_id):
    """Run the real Acknowledgment.sh for a coreId, NACK allowed, and return its own log."""
    result = runner.run(os.path.join(ACK_DIR, "Acknowledgment.sh"),
                        [core_id, "", "MIX", "1", "TRUE", logs], timeout=120)
    log = ""
    for path in sorted(glob_logs("COREID_%s.log" % core_id)):
        with open(path) as f:
            log += f.read()
    return result, log


def glob_logs(name):
    found = []
    for root, _dirs, files in os.walk(logs):
        found += [os.path.join(root, f) for f in files if f == name]
    return found


taken = [n for n in (SENDER, RECEIVER) if client.exists("accounts/" + n)] + \
        [n for n in (TEMPLATE, SIMPLE) if route_id(n)] + \
        [n for n in (APPLICATION,) if client.exists("applications/" + n)]
c.check("none of the throwaway names exist yet", not taken, taken)
if taken:
    c.info("refusing to run: remove %s by hand, or change st_object_prefix" % taken)
    client.logout()
    sys.exit(c.done())

made_accounts = []
logs = harness.scratch("zztest_pesit_")
mine = []

try:
    # -- the two accounts, each with a PeSIT site named after the other -------
    for name in (SENDER, RECEIVER):
        created('created the throwaway account "%s"' % name, client.post("accounts", {
            "name": name, "type": "user", "uid": "1050", "gid": "1050", "homeFolder": "/home/" + name,
            "transfersWebServiceAllowed": True,
            "user": {"name": name, "passwordCredentials": {"password": PASSWORD}}}))
        made_accounts.append(name)

    for owner, partner in ((RECEIVER, SENDER), (SENDER, RECEIVER)):
        created('%s has a PeSIT site "%s", pointing at this server' % (owner, partner),
                client.post("sites", {"type": "pesit", "protocol": "pesit", "name": partner, "account": owner,
                                      "host": PESIT_HOST, "port": PESIT_PORT, "transferType": "unspecified",
                                      "storeAndForwardMode": "PRESERVE", **PESIT_SITE_DEFAULTS}))

    for owner, label in ((RECEIVER, "DONT_SEND"), (SENDER, "SEND_FILENAME")):
        created("%s has a default transfer profile %s" % (owner, PROFILE),
                client.post("transferProfiles", {
                    "name": PROFILE, "account": owner, "default": True,
                    "sendMapping": "/" + SENT_FILE, "receiveMapping": "${pesit.fileName}",
                    "fileLabelOption": label, "transferMode": "BINARY",
                    "recordFormat": "Variable", "recordLength": 2048}))

    # -- the file to send, and the folders --------------------------------------
    with st_client.EndUserClient(config["st_server"], ENDUSER_PORT, SENDER, PASSWORD) as eu:
        response = eu.upload("/" + SENT_FILE, SENT_CONTENT, SENT_FILE)
        c.check("the sender holds the one file to send", response.status in (200, 201, 204), response.status)
        response = eu.create_folder("returned")
        c.check("the sender has a /returned folder", response.status in (200, 201), response.status)
    with st_client.EndUserClient(config["st_server"], ENDUSER_PORT, RECEIVER, PASSWORD) as eu:
        for folder in ("nack", "ack"):
            response = eu.create_folder(folder)
            c.check("the receiver has a /%s folder" % folder, response.status in (200, 201), response.status)

    # -- what forwards a file that lands in /ack ---------------------------------
    created("the receiver can push on over SSH, to the sender's /returned",
            client.post("sites", {"type": "ssh", "protocol": "ssh", "name": RETURN_SITE, "account": RECEIVER,
                                  "host": SSH_HOST, "port": SSH_PORT, "userName": SENDER, "usePassword": True,
                                  "password": PASSWORD, "transferType": "partner", "uploadFolder": "/returned"}))
    created("an Advanced Routing application", client.post(
        "applications", {"type": "AdvancedRouting", "name": APPLICATION}))
    created("a subscription on /ack, fed by the PeSIT site", client.post("subscriptions", {
        "type": "AdvancedRouting", "account": RECEIVER, "application": APPLICATION, "folder": "/ack",
        "transferConfigurations": [{"tag": "PARTNER-IN", "outbound": False, "site": SENDER}]}))
    subscription_id = next((s["id"] for s in results("subscriptions", {"account": RECEIVER})), None)
    created("a route template", client.post("routes", {"name": TEMPLATE, "type": "TEMPLATE",
                                                      "conditionType": "MATCH_ALL"}))
    created("a simple route that pushes the file on", client.post("routes", {
        "type": "SIMPLE", "name": SIMPLE, "conditionType": "ALWAYS", "condition": True,
        "steps": [{"type": "SendToPartner", "status": "ENABLED", "conditionType": "ALWAYS", "autostart": False,
                   "usePrecedingStepFiles": False, "fileFilterExpressionType": "GLOB", "fileFilterExpression": "*",
                   "transferSiteExpressionType": "LIST", "transferSiteExpression": RETURN_SITE + "#!#CVD#!#",
                   "actionOnStepFailure": "FAIL"}]}))
    created("a composite route on the subscription, running it", client.post("routes", {
        "type": "COMPOSITE", "account": RECEIVER, "name": COMPOSITE, "conditionType": "MATCH_ALL",
        "routeTemplate": route_id(TEMPLATE), "subscriptions": [subscription_id],
        "steps": [{"type": "ExecuteRoute", "status": "ENABLED", "autostart": False,
                   "executeRoute": route_id(SIMPLE)}]}))

    with runner.real_credentials(BASH_TREE, config):
        # -- 1. NACK -----------------------------------------------------------------
        nack_core = pull("/nack")
        mine.append(nack_core)
        result, log = acknowledge(nack_core)
        c.check("Acknowledgment.sh runs without an error", result.returncode == 0,
                (result.stdout + result.stderr).strip()[-300:])
        c.check("with no outbound transfer, it takes the NACK branch", "Sending NACK" in log, log[-400:])
        c.check("and its log says the NACK was sent", "ACK/NACK sent successfully" in log, log[-400:])
        c.check('the transfer is now "nack"', wait_until(lambda: ack_status(nack_core) == "nack", 30),
                ack_status(nack_core))

        # -- 2. ACK ------------------------------------------------------------------
        ack_core = pull("/ack")
        mine.append(ack_core)
        c.check("the route pushed the file on, under the same coreId",
                wait_until(lambda: outbound_processed(ack_core)), ack_core)
        result, log = acknowledge(ack_core)
        c.check("Acknowledgment.sh runs without an error", result.returncode == 0,
                (result.stdout + result.stderr).strip()[-300:])
        c.check("with the outbound transfer there, it takes the ACK branch", "ACK_TYPE: ACK" in log, log[-400:])
        c.check("and its log says the ACK was sent", "ACK/NACK sent successfully" in log, log[-400:])
        c.check('the transfer is now "ack"', wait_until(lambda: ack_status(ack_core) == "ack", 30),
                ack_status(ack_core))

        # -- 3. IteratePesitInbounds.sh ---------------------------------------------
        ready = pull("/ack")
        not_ready = pull("/nack")
        mine += [ready, not_ready]
        wait_until(lambda: outbound_processed(ready))

        since = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc)
                                            - datetime.timedelta(hours=1))
        window = results("logs/transfers", {"protocol": "pesit", "direction": "Incoming", "status": "Processed",
                                            "endTimeAfter": since, "limit": 500})
        # Anything of an account carrying this check's prefix is a throwaway of
        # this or an earlier run; anything else belongs to someone, and is not
        # for this check to acknowledge
        others = sorted({e.get("coreId") for e in window if e.get("pesitAckStatus") is None
                         and e.get("coreId") not in mine
                         and not str(e.get("account", "")).upper().startswith(PESIT_PREFIX.upper())})
        if others:
            c.info("IteratePesitInbounds.sh is not run: %d unacknowledged PeSIT transfer(s) in the last hour "
                   "are not this check's, and it would acknowledge them too" % len(others))
        else:
            elsewhere = harness.scratch("zztest_elsewhere_")
            result = subprocess.run(["bash", os.path.join(ACK_DIR, "IteratePesitInbounds.sh"), "1", "0", "", logs],
                                    cwd=elsewhere, capture_output=True, text=True, timeout=300)
            c.check("IteratePesitInbounds.sh, run from another folder, runs without an error",
                    result.returncode == 0, (result.stdout + result.stderr).strip()[-300:])
            c.check("it ACKs the transfer that was pushed on",
                    wait_until(lambda: ack_status(ready) == "ack", 30), ack_status(ready))
            c.check("and leaves the one with no outbound transfer for a later run",
                    ack_status(not_ready) is None, ack_status(not_ready))

except SystemExit:
    pass

finally:
    # Nothing of this check's stays unacknowledged for someone else's run to find
    try:
        with runner.real_credentials(BASH_TREE, config):
            for core_id in mine:
                if ack_status(core_id) is None:
                    acknowledge(core_id)
        left = [core_id for core_id in mine if ack_status(core_id) is None]
        c.check("every transfer this check made is acknowledged", not left, left)
    except Exception as e:  # cleanup carries on regardless
        c.info("could not acknowledge what was left: %s" % e)

    for name in (COMPOSITE, SIMPLE, TEMPLATE):
        rid = route_id(name)
        if rid:
            client.delete("routes/" + rid)
    for account in made_accounts:
        for sub in results("subscriptions", {"account": account}):
            client.delete("subscriptions/" + sub["id"])
    if client.exists("applications/" + APPLICATION):
        client.delete("applications/" + APPLICATION)
    for account in made_accounts:
        for site in results("sites", {"account": account}):
            client.delete("sites/" + site["id"])
        for profile in results("transferProfiles", {"account": account}):
            client.delete("transferProfiles/" + profile["id"])
        # Deleting an account leaves its files on disk, so remove them first
        try:
            with st_client.EndUserClient(config["st_server"], ENDUSER_PORT, account, PASSWORD) as eu:
                for folder in ("", "nack", "ack", "returned"):
                    for name in eu.list_folder(folder) or []:
                        eu.delete_file((folder + "/" if folder else "") + name)
                    if folder:
                        eu.delete_file(folder)
        except st_client.STError as e:
            c.info("could not remove the files of %s: %s" % (account, e))
        client.delete("accounts/" + account)

    leftovers = [n for n in (SENDER, RECEIVER) if client.exists("accounts/" + n)]
    leftovers += [n for n in (COMPOSITE, SIMPLE, TEMPLATE) if route_id(n)]
    leftovers += [APPLICATION] if client.exists("applications/" + APPLICATION) else []
    c.check("everything this check created was removed", not leftovers, leftovers)
    client.logout()

c.info("logs of the acknowledgment scripts: %s" % logs)
c.info("%d API calls issued by the verification client (not counting the scripts' own calls)" % client.calls)

sys.exit(c.done())
