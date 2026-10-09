#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the newer examples end to end, as one Advanced
Routing flow, against a throwaway account, and checks every step through the
API:

  EndUser 02.Files/02.files_name_POST_folder.sh        the account's folders
  EndUser 02.Files/08.fileOperations_POST_upload.sh    a file to pull
  06.TransferSites/02.sites_POST_ssh.sh, 03.sites_GET.sh
  07.Subscriptions/02.subscriptions_POST.sh, 03..._triggerfile.sh, 01..._GET.sh
  09.CompositeRoutes/03.routes_POST_simple_compress.sh, 04..._decompress.sh,
                     05.routes_POST_composite_subscription.sh, 06.routes_GET.sh
  15.Transfers/01.transfers_operations_POST_pull.sh
  16.TransferLogs/01.logs_transfers_GET.sh, 02.logs_transfers_GET_billable.sh
  and then the clean-up examples, in reverse:
  09.CompositeRoutes/07.routes_id_DELETE.sh, 07.Subscriptions/04..._DELETE.sh,
  06.TransferSites/04.sites_id_DELETE.sh

The proof that the pieces fit together: after the pull, the uploaded file
comes back through the subscription, the composite route and the Compress
route, and lands in the account's own /delivered folder as
compressed_files.zip_PUSHED. The partner is SecureTransport itself, over SSH,
logged in as the same account.

The Admin examples are written for the account "john", the SSH port 8022 and
fixed object names. The account and the port are settings of the examples
(ST_EXAMPLE_ACCOUNT and ST_SSH_PORT), so they run with the throwaway account and
the configured port in their environment, as a person would set them. The
object names have no setting: the scripts run as name-substituted copies (see
"Substituted-copy fallbacks" in the README), so that nothing already on the
server is touched:

  ST_EXAMPLE_ACCOUNT (john)    = <prefix>chain, created and deleted here
  ST_SSH_PORT (8022)           = st_ssh_port from the config
  AdvancedRoutingApplication   -> <prefix>ARApplication
  SimpleRoute_Compress, SimpleRoute_Decompress, SimpleRouteName
                               -> the same names with the prefix
  RouteFromPartner             -> <prefix>RouteTemplate, created and deleted here
  PARTNER_HOST                 -> st_ssh_host from the config

The request bodies and the lookups are the scripts' own. The EndUser examples
need no substitution: they run as the throwaway account, through
set_variables.local.sh, as a person would run them.

Two parts need 5.5-20260924 or later, and are skipped on an older server: the
trigger-file subscription (03.subscriptions_POST_triggerfile.sh) and the
billable count.

Refuses to run if the throwaway account, template, application or simple
routes already exist. Everything is removed again in a finally block, even
when a step fails, including the files left in the account's home folder.

Needs --write and st_allow_writes="yes". Optional settings in
integration.conf: st_enduser_port, st_ssh_host, st_ssh_port and
st_chain_wait_seconds, see integration.conf.example.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the subscription, route and transfer scripts for real")

c = st_client.Checker("Sites, subscriptions, routes, a pull and the transfer log, run for real "
                      "as one flow")

PREFIX = config.get("st_object_prefix") or "ZZTEST_"
ACCOUNT = PREFIX + "chain"
PASSWORD = harness.new_password()
TEMPLATE = PREFIX + "RouteTemplate"
APPLICATION = PREFIX + "ARApplication"
SIMPLE_COMPRESS = PREFIX + "SimpleRoute_Compress"
SIMPLE_DECOMPRESS = PREFIX + "SimpleRoute_Decompress"
SIMPLE_NAME = PREFIX + "SimpleRouteName"
COMPOSITE = "CompositeRoute_Subscription"
FOLDERS = ["outbound-drop", "delivered", "inbox", "inbox-trigger"]
UPLOAD_NAME = "zztest_upload.txt"
UPLOAD_CONTENT = "A file for the integration check, pulled, compressed and pushed.\n"

ENDUSER_PORT = harness.ports(config).enduser
SSH_HOST = config.get("st_ssh_host") or config["st_server"]
WAIT = int(config.get("st_chain_wait_seconds") or "90")
NEW_RELEASE = "5.5-20260924"

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
FILES_DIR = os.path.join(ENDUSER_TREE, "02.Files")

# The scripts this check runs, in order, as name-substituted copies with the account and the port in their environment. The offline
# suite checks that every name in SUBS is substituted out of each of them, and that none names john or port 8022 except as the
# default of its setting.
ADMIN_SCRIPTS = [
    "06.TransferSites/02.sites_POST_ssh.sh", "06.TransferSites/03.sites_GET.sh",
    "07.Subscriptions/02.subscriptions_POST.sh", "07.Subscriptions/03.subscriptions_POST_triggerfile.sh",
    "07.Subscriptions/01.subscriptions_GET.sh",
    "09.CompositeRoutes/03.routes_POST_simple_compress.sh", "09.CompositeRoutes/04.routes_POST_simple_decompress.sh",
    "09.CompositeRoutes/05.routes_POST_composite_subscription.sh", "09.CompositeRoutes/06.routes_GET.sh",
    "15.Transfers/01.transfers_operations_POST_pull.sh",
    "16.TransferLogs/01.logs_transfers_GET.sh", "16.TransferLogs/02.logs_transfers_GET_billable.sh",
    "09.CompositeRoutes/07.routes_id_DELETE.sh", "07.Subscriptions/04.subscriptions_id_DELETE.sh",
    "06.TransferSites/04.sites_id_DELETE.sh",
]


def admin_script(relative, args=None):
    """Run a name-substituted copy of an Admin bash example, with the throwaway account and the SSH port set, and check it ran."""
    with runner.substituted_copy(os.path.join(BASH_TREE, relative), SUBS) as copy:
        # Never run a copy that still names a real object: a renamed variable in
        # an example would otherwise send it at "john" or the real application
        with open(copy) as f:
            text = f.read()
        still = runner.unsubstituted(text, SUBS) + runner.hardcoded_settings(text)
        if still:
            c.check("%s: every name was substituted before running it" % relative, False, still)
            raise SystemExit
        result = runner.run(copy, args, timeout=120, env=SETTINGS)
    c.check("%s runs without an error (name-substituted copy)" % relative,
            result.returncode == 0, (result.stdout + result.stderr).strip()[-300:])
    return result


def enduser_script(name, args=None):
    """Run a real, unmodified EndUser example as the throwaway account."""
    result = runner.run(os.path.join(FILES_DIR, name), args, timeout=120)
    c.check("EndUser %s runs without an error" % name, result.returncode == 0,
            (result.stdout + result.stderr).strip()[-300:])
    return result


def results(path, params=None):
    return (client.get(path, params=params).json() or {}).get("result", [])


def sites():
    return {s.get("name"): s for s in results("sites", {"account": ACCOUNT})}


def subscriptions():
    return {s.get("folder"): s for s in results("subscriptions", {"account": ACCOUNT})}


def route_id(name, route_type=None):
    for r in results("routes", {"name": name}):
        if route_type is None or r.get("type") == route_type:
            if r.get("type") != "COMPOSITE" or r.get("account") == ACCOUNT:
                return r.get("id")
    return None


def listing(stdout, after):
    """The non-empty lines a script printed after a heading line."""
    lines = stdout.split(after, 1)[1].splitlines()[1:] if after in stdout else []
    return [line for line in lines if line.strip()]


def total(params):
    return ((client.get("logs/transfers", params=dict(params, limit=1)).json() or {})
            .get("resultSet", {}).get("totalCount"))


client = harness.connect(config, c, mock=("the bundled mock does not implement /sites, /subscriptions, /routes, "
                                          "/transfers or the EndUser API; run this against a real server to exercise it"))

SSH_PORT = harness.ports(config, client).ssh
SUBS = runner.chain_substitutions(PREFIX, SSH_HOST)
SETTINGS = runner.chain_environment(PREFIX, SSH_PORT)
assert SETTINGS["ST_EXAMPLE_ACCOUNT"] == ACCOUNT  # the scripts act on the account this check creates and deletes

new_release = st_client.server_release_at_least(client, NEW_RELEASE)
if not new_release:
    c.info("this server is older than %s: the trigger-file subscription and the "
           "billable count are skipped" % NEW_RELEASE)

taken = [n for n in (ACCOUNT,) if client.exists("accounts/" + n)] + \
        [n for n in (TEMPLATE, SIMPLE_COMPRESS, SIMPLE_DECOMPRESS, SIMPLE_NAME) if route_id(n)] + \
        [n for n in (APPLICATION,) if client.exists("applications/" + n)]
c.check("none of the throwaway names exist yet", not taken, taken)
if taken:
    c.info("refusing to run: remove %s by hand, or change st_object_prefix" % taken)
    client.logout()
    sys.exit(c.done())

created_account = False
work = harness.scratch("zztest_chain_")
upload_path = os.path.join(work, UPLOAD_NAME)
with open(upload_path, "w") as f:
    f.write(UPLOAD_CONTENT)

eu_config = dict(config, st_port=ENDUSER_PORT, st_user=ACCOUNT, st_password=PASSWORD)
os.environ["PARTNER_PASSWORD"] = PASSWORD

try:
    # -- the throwaway account and route template ---------------------------
    response = client.post("accounts", {
        "name": ACCOUNT, "type": "user", "uid": "1050", "gid": "1050",
        "homeFolder": "/home/" + ACCOUNT, "transfersWebServiceAllowed": True,
        "user": {"name": ACCOUNT, "passwordCredentials": {"password": PASSWORD}},
    })
    created_account = response.status == 201
    c.check('created the throwaway account "%s"' % ACCOUNT, created_account, response.text[:200])
    if not created_account:
        raise SystemExit

    response = client.post("routes", {"name": TEMPLATE, "type": "TEMPLATE", "conditionType": "MATCH_ALL",
                                      "description": "Integration check 31"})
    template_id = route_id(TEMPLATE, "TEMPLATE")
    c.check('created the throwaway route template "%s"' % TEMPLATE, bool(template_id), response.text[:200])
    if not template_id:
        raise SystemExit

    # -- EndUser: the folders, and a file to pull ---------------------------
    with runner.real_credentials(ENDUSER_TREE, eu_config):
        for folder in FOLDERS:
            result = enduser_script("02.files_name_POST_folder.sh", [folder])
            c.check("the folder %s was created (the script printed a 2xx)" % folder,
                    re.search(r"^HTTP 2\d\d$", result.stdout, re.M) is not None, result.stdout[-200:])
        enduser_script("08.fileOperations_POST_upload.sh", [upload_path, "outbound-drop"])

    with st_client.EndUserClient(config["st_server"], ENDUSER_PORT, ACCOUNT, PASSWORD) as eu:
        for folder in FOLDERS:
            c.check("the folder %s can be listed" % folder, eu.list_folder(folder) is not None)
        got = eu.download("outbound-drop/" + UPLOAD_NAME)
        c.check("the uploaded file is in outbound-drop, with its content",
                got.status == 200 and got.text == UPLOAD_CONTENT, (got.status, got.text[:80]))

    with runner.real_credentials(BASH_TREE, config):
        # -- 06.TransferSites -----------------------------------------------
        admin_script("06.TransferSites/02.sites_POST_ssh.sh")
        found = sites()
        pull, push = found.get("SSH_PULL") or {}, found.get("SSH_PUSH") or {}
        c.check("SSH_PULL and SSH_PUSH now exist for the account", pull and push, sorted(found))
        c.check("SSH_PULL logs in with a password, on the SSH port",
                pull.get("usePassword") is True and str(pull.get("port")) == SSH_PORT,
                (pull.get("usePassword"), pull.get("port")))
        c.check("SSH_PULL keeps the rename EL as written",
                (pull.get("postTransmissionActions") or {}).get("doAsIn") == "${stenv.target}_PULLED",
                pull.get("postTransmissionActions"))
        c.check("SSH_PUSH uploads to /delivered", push.get("uploadFolder") == "/delivered",
                push.get("uploadFolder"))

        result = admin_script("06.TransferSites/03.sites_GET.sh")
        lines = listing(result.stdout, "Get only its SSH sites")
        c.check("03.sites_GET.sh lists exactly the account's two SSH sites",
                len(lines) == 2 and all(n in result.stdout for n in ("SSH_PULL", "SSH_PUSH")), lines)

        # -- 07.Subscriptions -----------------------------------------------
        result = admin_script("07.Subscriptions/02.subscriptions_POST.sh")
        app = client.get("applications/" + APPLICATION).json() or {}
        c.check("the application exists, of type AdvancedRouting", app.get("type") == "AdvancedRouting",
                app.get("type"))
        inbox = subscriptions().get("/inbox") or {}
        c.check("the subscription on /inbox exists, using the application",
                inbox.get("application") == APPLICATION, inbox.get("application"))
        c.check("its transfer configuration pulls with SSH_PULL",
                st_client.find_value(inbox.get("transferConfigurations"), "SSH_PULL") is not None,
                inbox.get("transferConfigurations"))
        c.check("the script printed the id of the new subscription",
                inbox.get("id") and ("New subscription ID: %s" % inbox.get("id")) in result.stdout,
                result.stdout[-200:])

        if new_release:
            admin_script("07.Subscriptions/03.subscriptions_POST_triggerfile.sh")
            trigger = subscriptions().get("/inbox-trigger") or {}
            actions = trigger.get("postTransmissionActions") or {}
            c.check("the trigger-file subscription keeps its condition, two backslashes and all",
                    actions.get("triggerOnConditionExpression") == r"${stenv['target'].matches('.*\\.trigger')?1:0}",
                    actions.get("triggerOnConditionExpression"))
            c.check("and waits for the trigger file", actions.get("submitFilterType") == "TRIGGER_FILE_CONTENT",
                    actions.get("submitFilterType"))

        result = admin_script("07.Subscriptions/01.subscriptions_GET.sh")
        lines = listing(result.stdout, "Get only its Advanced Routing subscriptions")
        c.check("01.subscriptions_GET.sh lists exactly the account's subscriptions",
                len(lines) == len(subscriptions()), lines)

        # -- 09.CompositeRoutes ---------------------------------------------
        for script, name, first in (("03.routes_POST_simple_compress.sh", SIMPLE_COMPRESS, "Compress"),
                                    ("04.routes_POST_simple_decompress.sh", SIMPLE_DECOMPRESS, "Decompress")):
            admin_script("09.CompositeRoutes/" + script)
            rid = route_id(name, "SIMPLE")
            steps = (client.get("routes/%s" % rid).json() or {}).get("steps", []) if rid else []
            c.check("%s exists, with %s then SendToPartner" % (name, first),
                    [s.get("type") for s in steps] == [first, "SendToPartner"], [s.get("type") for s in steps])

        admin_script("09.CompositeRoutes/05.routes_POST_composite_subscription.sh")
        cid = route_id(COMPOSITE, "COMPOSITE")
        composite = (client.get("routes/%s" % cid).json() or {}) if cid else {}
        c.check("the composite route exists for the account", bool(cid))
        c.check("it inherits the template", composite.get("routeTemplate") == template_id,
                composite.get("routeTemplate"))
        c.check("it is linked to the /inbox subscription",
                inbox.get("id") in (composite.get("subscriptions") or []), composite.get("subscriptions"))
        c.check("it runs the Compress route",
                st_client.find_value(composite.get("steps"), route_id(SIMPLE_COMPRESS, "SIMPLE")) is not None,
                composite.get("steps"))

        result = admin_script("09.CompositeRoutes/06.routes_GET.sh")
        composite_lines = [line for line in result.stdout.splitlines() if "  template=" in line]
        c.check("06.routes_GET.sh lists exactly the account's composite route",
                len(composite_lines) == 1 and COMPOSITE in composite_lines[0], composite_lines)
        c.check("and the steps of the Compress route",
                "  Compress  ENABLED" in result.stdout and "  SendToPartner  ENABLED" in result.stdout,
                result.stdout[-200:])

        # -- 15.Transfers: the pull, and the whole flow behind it -------------
        result = admin_script("15.Transfers/01.transfers_operations_POST_pull.sh")
        c.check("the pull is accepted (HTTP 202)", re.search(r"^HTTP 202$", result.stdout, re.M) is not None,
                result.stdout[-200:])

        with st_client.EndUserClient(config["st_server"], ENDUSER_PORT, ACCOUNT, PASSWORD) as eu:
            delivered = harness.settled(lambda: [n for n in (eu.list_folder("delivered") or []) if n.startswith("compressed_files.zip")],
                                        bool, WAIT, 3) or []
            inbox_files = eu.list_folder("inbox")
        c.check("within %ds, the file came back pulled, compressed and pushed to /delivered" % WAIT,
                delivered == ["compressed_files.zip_PUSHED"], delivered or ("inbox holds", inbox_files))

        # -- 16.TransferLogs --------------------------------------------------
        low = total({"account": ACCOUNT})
        result = admin_script("16.TransferLogs/01.logs_transfers_GET.sh", [ACCOUNT])
        high = total({"account": ACCOUNT})
        match = re.search(r"^(\d+) transfer\(s\) of '%s' in the log" % re.escape(ACCOUNT), result.stdout, re.M)
        got = int(match.group(1)) if match else None
        c.check("01.logs_transfers_GET.sh counts the account's transfers as the API does "
                "(%s, API %s..%s)" % (got, low, high),
                got is not None and low is not None and low <= got <= high)
        c.check("the upload and the pull are both in the log", (got or 0) >= 2, got)

        if new_release:
            result = admin_script("16.TransferLogs/02.logs_transfers_GET_billable.sh", ["1", ACCOUNT])
            today = re.search(r"^\s+\d{4}-\d{2}-\d{2}\s+(\d+)\s*$", result.stdout, re.M)
            c.check("02.logs_transfers_GET_billable.sh counts at least one billable transfer today",
                    today is not None and int(today.group(1)) >= 1, result.stdout[-200:])

        # -- the clean-up examples, in reverse ------------------------------
        admin_script("09.CompositeRoutes/07.routes_id_DELETE.sh")
        left = [n for n, t in ((COMPOSITE, "COMPOSITE"), (SIMPLE_COMPRESS, "SIMPLE"),
                               (SIMPLE_DECOMPRESS, "SIMPLE")) if route_id(n, t)]
        c.check("07.routes_id_DELETE.sh removed the composite and simple routes", not left, left)
        c.check("and left the template alone", route_id(TEMPLATE, "TEMPLATE") == template_id)

        admin_script("07.Subscriptions/04.subscriptions_id_DELETE.sh")
        c.check("04.subscriptions_id_DELETE.sh removed the subscriptions", not subscriptions(),
                sorted(subscriptions()))
        c.check("and the application", not client.exists("applications/" + APPLICATION))

        admin_script("06.TransferSites/04.sites_id_DELETE.sh")
        c.check("04.sites_id_DELETE.sh removed both sites", not sites(), sorted(sites()))

except SystemExit:
    pass

finally:
    # Whatever a failed step left behind, removed through the API
    for name, route_type in ((COMPOSITE, "COMPOSITE"), (SIMPLE_COMPRESS, "SIMPLE"),
                             (SIMPLE_DECOMPRESS, "SIMPLE"), (SIMPLE_NAME, "SIMPLE"), (TEMPLATE, "TEMPLATE")):
        rid = route_id(name, route_type)
        if rid:
            client.delete("routes/" + rid)
    if created_account:
        for sub in subscriptions().values():
            client.delete("subscriptions/" + sub["id"])
    if client.exists("applications/" + APPLICATION):
        client.delete("applications/" + APPLICATION)
    if created_account:
        for site in sites().values():
            client.delete("sites/" + site["id"])
        # Deleting an account leaves its files on disk, so remove them first
        try:
            with st_client.EndUserClient(config["st_server"], ENDUSER_PORT, ACCOUNT, PASSWORD) as eu:
                for folder in FOLDERS:
                    for name in eu.list_folder(folder) or []:
                        eu.delete_file(folder + "/" + name)
                    eu.delete_file(folder)
        except st_client.STError as e:
            c.info("could not remove the account's files: %s" % e)
        client.delete("accounts/" + ACCOUNT)

    leftovers = [n for n in (COMPOSITE, SIMPLE_COMPRESS, SIMPLE_DECOMPRESS, SIMPLE_NAME, TEMPLATE) if route_id(n)]
    leftovers += [APPLICATION] if client.exists("applications/" + APPLICATION) else []
    leftovers += [ACCOUNT] if client.exists("accounts/" + ACCOUNT) else []
    c.check("everything this check created was removed", not leftovers, leftovers)
    os.environ.pop("PARTNER_PASSWORD", None)
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own calls)"
       % client.calls)

sys.exit(c.done())
