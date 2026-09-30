#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Triggers a real, live PeSIT pull between two real,
pre-existing accounts on this server - "jack" and "john", already wired
together as a self-referential PeSIT partner pair (confirmed directly: site
"jack" belongs to account "john" and site "john" belongs to account "jack",
both pointing at this same server's own PeSIT port) - then runs the real,
unmodified Acknowledgment.sh against the resulting transfer's coreId, and
verifies it takes the NACK branch (no correlated outbound transfer exists to
ACK against).

MANUAL ONLY, for reasons distinct from every other check here: jack and john
are not throwaway objects this project created. They are real, populated,
actively used accounts already on this shared lab (jack's home folder alone
has a copy of "Claude.dmg", "Sublime Text.app.zip" and "plugins.zip" -
someone's real files, not fixtures; there is also unrelated "mcp-test-*"
configuration on this same server, evidence of other tooling actively using
it) - and this check briefly changes jack's real password to clean up after
itself. Confirmed directly, before writing this:

  - `POST /transfers/operations?operation=pull` with no filename specified
    does not pull a disposable, predictable file. It pulls WHATEVER the
    sending side's own wildcard mapping (`sendMapping: "/*"` on both sites'
    transfer profiles) hands over - confirmed empirically to grab an
    arbitrary real file from the partner's entire home folder, not
    something this check controls. The one manual run of this exact
    experiment, done to confirm the mechanism before writing this check,
    pulled a real 251878-byte training document out of john's folder into
    jack's.
  - The local filename it lands under IS deterministic - the transfer
    profile's own `receiveMapping` evaluates `${pesit.fileName}` to the
    literal string "TP" every time, confirmed directly - so this check
    knows exactly what to delete afterward without needing to browse
    jack's whole folder. Only the CONTENT is an unpredictable real file
    copied out of john's home folder each run - the source file itself is
    left untouched (`storeAndForwardMode: PRESERVE` on both sites,
    confirmed directly: john's own file listing was unchanged, byte for
    byte, before and after the pull).
  - The admin API has no file-browsing or file-delete endpoint of its own -
    only the EndUser API does, which needs a real login. Since there is no
    way to know jack's actual password, this check temporarily resets it
    (capturing and restoring the exact original password hash via the
    account's own `passwordDigest` field - confirmed directly to round-trip
    byte for byte), logs in once as jack, deletes the one file ("/TP") this
    check's own pull created, and restores the original password hash
    before doing anything else, verifying the restore independently.
  - Sending a NACK is not a side-effect-free status flip: confirmed
    directly, it creates its OWN additional logged sub-transaction sharing
    the same coreId - one more small, real trace left on this shared
    account's transfer history, unavoidable if this branch is exercised at
    all.

This only exercises Acknowledgment.sh's NACK branch. The ACK branch would
need a real auto-relay route built on this same shared account pair (so a
correlated outbound transfer exists to acknowledge positively) - deliberately
not attempted here: more setup work, and more real risk to accounts this
project does not own. See .claude/skills/st-api-gotchas/SKILL.md for all of
the above.

Needs --write, st_allow_writes="yes", AND
--i-understand-this-touches-real-shared-accounts on the command line - unlike
every other object --write touches in this project, jack and john are not
disposable objects this project created.
"""
import base64
import os
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run a real PeSIT pull and Acknowledgment.sh")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

if "--i-understand-this-touches-real-shared-accounts" not in sys.argv:
    st_client.skip("this check needs --i-understand-this-touches-real-shared-accounts too - "
                   "read this file's own docstring first: jack and john are real, populated "
                   "accounts on this lab, not fixtures this project created")

c = st_client.Checker("Acknowledgment.sh (NACK branch), run for real from "
                       "Admin/API 2.0/bash/90.EndToEndAcknowledgment")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
ACK_DIR = os.path.join(BASH_TREE, "90.EndToEndAcknowledgment")
PULL_ACCOUNT = "jack"
PULL_SITE = "john"
TRANSFER_PROFILE = "TP"
PULLED_FILENAME = "TP"
ENDUSER_PORT = config.get("st_enduser_port") or str(int(config["st_port"]) - 1)

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /transfers, /logs/transfers or PeSIT sites; "
           "run this against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

jack_response = client.get("accounts/%s" % PULL_ACCOUNT, params={"type": "user"})
john_response = client.get("accounts/%s" % PULL_SITE, params={"type": "user"})
if jack_response.status != 200 or john_response.status != 200:
    c.info('accounts "jack" and/or "john" do not exist on this server - this check is '
           "written specifically for this lab's own pre-existing PeSIT partner pair, "
           "not something it creates. Skipping.")
    client.logout()
    sys.exit(c.done())


def wait_until(predicate, timeout=60, interval=2):
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(interval)
    return predicate()


original_digest = jack_response.json()["user"]["passwordCredentials"]["passwordDigest"]
c.check("captured jack's original password hash", bool(original_digest))

temp_password_set = False
eu_client = None

try:
    temp_password = "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"
    resp = client.patch("accounts/%s" % PULL_ACCOUNT, [
        {"op": "replace", "path": "/user/passwordCredentials/password", "value": temp_password},
    ])
    temp_password_set = resp.status == 204
    c.check("set a temporary password on jack, to clean up with afterward",
            temp_password_set, resp.text[:200])
    if not temp_password_set:
        raise SystemExit(c.done())

    # -- trigger a real PeSIT pull: jack pulls from site "john" --------------
    resp = client.post("transfers/operations",
                        {"accountName": PULL_ACCOUNT, "site": PULL_SITE,
                         "destinationDirectory": "/", "transferProfile": TRANSFER_PROFILE,
                         "awaitResult": "true"},
                        params={"operation": "pull"})
    c.check("the pull operation was accepted", resp.status == 202, resp.text[:300])
    link = (resp.json() or {}).get("link", "")
    query = urllib.parse.urlparse(link).query
    operation_index = urllib.parse.parse_qs(query).get("operationIndex", [None])[0]
    c.check("the pull response named an operationIndex to track it by",
            bool(operation_index), link)

    entry = wait_until(lambda: next(
        (e for e in (client.get("logs/transfers",
                                params={"operationIndex": operation_index}).json() or {})
         .get("pullEntries", []) if e.get("status") == "Processed"), None))
    c.check("the pull produced a Processed inbound PeSIT transfer", entry is not None, entry)
    if entry is None:
        raise SystemExit(c.done())

    core_id = entry.get("coreId")
    c.check("the transfer carries a coreId to acknowledge against", bool(core_id), entry)
    c.info("coreId: %s, localFilename: %s, pulled from account: %s"
           % (core_id, entry.get("localFilename"), PULL_SITE))

    # -- run the real, unmodified Acknowledgment.sh ---------------------------
    with runner.real_credentials(BASH_TREE, config):
        result = runner.run(os.path.join(ACK_DIR, "Acknowledgment.sh"), args=[core_id], timeout=90)
    c.check("Acknowledgment.sh runs without a shell level error", result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")

    # The script logs its own progress to a file, not stdout - stdout only
    # ever gets the one "All log files will be saved in: ..." line, printed
    # before the log directory even has a coreId-specific file in it.
    log_dir_line = next((l for l in result.stdout.splitlines() if "saved in:" in l), "")
    log_dir = log_dir_line.split("saved in:", 1)[1].strip() if log_dir_line else ""
    log_file = os.path.join(log_dir, "COREID_%s.log" % core_id) if log_dir else ""
    log_contents = ""
    if log_file and os.path.exists(log_file):
        with open(log_file) as f:
            log_contents = f.read()
    c.check("found the script's own per-coreId log file", bool(log_contents), log_file)
    c.check("its own log confirms it took the NACK branch (no outbound leg exists to ACK)",
            "Sending NACK" in log_contents, log_contents[-400:])

    # -- verify the NACK actually landed on this coreId -----------------------
    # A coreId-filtered /logs/transfers query returns the same "result" shape
    # every other logs/transfers listing does - "pullEntries" is specific to
    # the operationIndex-tracking query used just above, not this one.
    verify = client.get("logs/transfers", params={"coreId": core_id}).json() or {}
    acked = any(e.get("coreId") == core_id and e.get("pesitAckStatus") == "nack"
               for e in verify.get("result", []))
    c.check('the original inbound transfer\'s pesitAckStatus is now "nack"', acked, verify)

finally:
    if temp_password_set:
        try:
            eu_client = st_client.EndUserClient(config["st_server"], ENDUSER_PORT,
                                                PULL_ACCOUNT, temp_password)
            eu_client.login()
            del_resp = eu_client.delete_file(PULLED_FILENAME)
            c.check('deleted the file this pull created ("/%s") from jack'
                    % PULLED_FILENAME, del_resp.status in (200, 204), del_resp.status)
        except st_client.STError as e:
            c.check("logged in as jack via EndUser to clean up the pulled file", False, str(e))
        finally:
            if eu_client is not None:
                try:
                    eu_client.logout()
                except st_client.STError:
                    pass

        resp = client.patch("accounts/%s" % PULL_ACCOUNT, [
            {"op": "replace", "path": "/user/passwordCredentials/passwordDigest",
             "value": original_digest},
        ])
        c.check("restored jack's original password hash", resp.status == 204, resp.text[:200])

        after = client.get("accounts/%s" % PULL_ACCOUNT, params={"type": "user"}).json() or {}
        after_digest = (after.get("user") or {}).get("passwordCredentials", {}).get("passwordDigest")
        c.check("jack's password hash matches the original exactly",
                after_digest == original_digest)

    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own curl calls)"
       % client.calls)

sys.exit(c.done())
