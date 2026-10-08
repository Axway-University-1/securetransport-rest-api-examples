#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 07.Subscriptions examples 05 to
13 (HEAD, GET one, PUT, PATCH, the Pull, ClearPullHistory and Purge operations,
the subscriptions of four other types, and their deletion with purge=true)
against throwaway subscriptions of one throwaway account, and reads each effect
back through the API.

The account has an SSH site that logs in to the lab's own SSH server as the
account itself, and a file in its own /in folder, so that a pull can really
fetch something:

  - 05/06 find a subscription by account, application and folder; a folder
    that is not there, an application in capitals and a wildcard find nothing
    (the filters are exact), and a second folder of the same application is
    told apart;
  - 07 sends the whole subscription back with one field changed: the pull
    site, the flow attribute and everything else stay; a raw PUT of a
    fragment, made once on a sacrificial subscription, silently drops them;
  - 08 adds one flow attribute and nothing else moves; it overwrites it;
  - 09 pulls a file into the folder (the file stays on the partner); with a
    pull history (retention 5 days) a file already pulled, and deleted from
    the folder, is not pulled again;
  - 10 clears the history, and the next pull fetches the file again;
  - 11 removes the whole folder and keeps the subscription;
  - 12 subscribes the account to a Basic, a HumanSystem, an MBFT and a
    StandardRouter application, each read back with its type; a second run is
    refused (unique anchor);
  - 13 deletes them with purge=true: their folders go too, and so do the
    applications.

The list of subscriptions is not trusted to answer completely at the first
read: a script is run again, a few times, when its lookup found nothing for a
subscription that is known to exist, and every read through the API waits for
the answer it expects.

Needs --write and st_allow_writes="yes". Refuses to start when an
example_subs_* account, application or site, or one of the Example*Application
applications that 12 creates, exists. The account gets a new random name and
user id on every run, because a home folder outlives its account and keeps its
owner (see st-api-gotchas). Removes the subscriptions, applications, site and
account in a finally block, and checks that nothing is left.
"""
import os
import random
import string
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the subscriptions examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Subscriptions, run for real from Admin/API 2.0/bash/07.Subscriptions (05 to 13)")
BASH = runner.path("Admin", "API 2.0", "bash")
FOLDER = os.path.join(BASH, "07.Subscriptions")
SUFFIX = "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(6))
ACCOUNT = "example_subs_" + SUFFIX
UID = str(random.randint(53000, 59999))
PASSWORD = "Ax" + "".join(random.choice(string.ascii_letters + string.digits) for _ in range(12)) + "1!"
APP, APP_B, SITE = "example_subs_ar", "example_subs_basic", "example_subs_site"
TYPE_APPS = {t: "Example%sApplication" % t for t in ("Basic", "HumanSystem", "MBFT", "StandardRouter")}
HOST = config["st_server"]
ENDUSER_PORT = config.get("st_enduser_port") or str(int(config["st_port"]) - 1)


def wait_until(predicate, seconds=30):
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            if predicate():
                return True
        except st_client.STError:
            pass
        time.sleep(1)
    try:
        return bool(predicate())
    except st_client.STError:
        return False


def script(name, args=None, expect_rc=0, retry=True):
    """Run an example. When its lookup found no subscription (retry=True: it exists, but the list is not
    always complete), run it again, up to five times."""
    for attempt in range(5):
        result = runner.run(os.path.join(FOLDER, name), args, timeout=120)
        out = result.stdout + result.stderr
        if retry and "Found 0 subscriptions" in out:
            time.sleep(2)
            continue
        break
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc, out.strip()[-400:])
    return out


def subs_of(account=ACCOUNT, **params):
    response = admin.get("subscriptions", params=dict({"account": account}, **params))
    return (response.json() or {}).get("result", []) if response.status == 200 else []


def find(application, folder, account=ACCOUNT):
    found = [s for s in subs_of(account, application=application) if s["folder"] == folder]
    return found[0] if len(found) == 1 else None


def read(sub_id):
    response = admin.get("subscriptions/" + sub_id)
    return response.json() if response.status == 200 else {}


def sub_body(application, folder, **more):
    body = {"type": "AdvancedRouting", "account": ACCOUNT, "application": application, "folder": folder}
    body.update(more)
    return body


def make_sub(label, body):
    response = admin.post("subscriptions", body)
    c.check("set up: " + label, response.status == 201, response.text[:300])
    return response.headers.get("Location", "").rsplit("/", 1)[-1]


def folder_names(client):
    listing = client.list_files()
    return [f.get("fileName") for f in (listing.json() or {}).get("files", [])] if listing.status == 200 else None


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /subscriptions or the protocol servers")
    admin.logout()
    sys.exit(c.done())
busy = [a for a in (APP, APP_B) + tuple(TYPE_APPS.values()) if admin.exists("applications/" + a)]
if busy or admin.get("accounts", params={"name": "example_subs_*"}).json().get("result") \
        or admin.get("sites", params={"name": "example_subs_*"}).json().get("result"):
    c.check("no example_subs_* account or site, and none of the applications this check makes, exists yet",
            False, "remove them first; this check will not touch them: %s" % busy)
    admin.logout()
    sys.exit(c.done())

servers = admin.get("servers").json()
servers = servers if isinstance(servers, list) else servers.get("result", [])
ssh_ports = [s["port"] for s in servers if s.get("protocol") == "ssh" and s.get("port")]
daemons = admin.get("daemons").json()
if not ssh_ports or daemons.get("sshStatus") != "Running":
    c.info("the SSH daemon must be running: the pull logs in to it")
    admin.logout()
    sys.exit(c.done())
ssh_port = ssh_ports[0]

subs_before = (admin.get("subscriptions", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount")
ids = {}
eu = None
left = None
try:
    response = admin.post("accounts", {"name": ACCOUNT, "type": "user", "uid": UID, "gid": UID, "homeFolder": "/home/" + ACCOUNT,
                                       "user": {"name": ACCOUNT, "passwordCredentials": {"password": PASSWORD}}})
    c.check("set up: the account " + ACCOUNT, response.status == 201, response.text[:200])
    for name, kind in ((APP, "AdvancedRouting"), (APP_B, "Basic")):
        response = admin.post("applications", {"type": kind, "name": name})
        c.check("set up: the %s application %s" % (kind, name), response.status == 201, response.text[:200])
    response = admin.post("sites", {"type": "ssh", "protocol": "ssh", "name": SITE, "account": ACCOUNT, "host": HOST, "port": str(ssh_port),
                                    "userName": ACCOUNT, "usePassword": True, "password": PASSWORD, "transferType": "partner",
                                    "downloadFolder": "/in", "downloadPattern": "*", "uploadFolder": "/out"})
    c.check("set up: the SSH site", response.status == 201, response.text[:200])

    eu = st_client.EndUserClient(HOST, ENDUSER_PORT, ACCOUNT, PASSWORD)
    eu.login()
    made = [None]

    def create_in():
        made[0] = eu.create_folder("in")
        return made[0].status == 201
    c.check("set up: the folder /in", wait_until(create_in, 20), (made[0].status, made[0].text[:200]))

    def upload(name, content=b"pulled by a subscription"):
        boundary = "----example_subs"
        body = ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n\r\n" % (boundary, name)).encode() \
            + content + ("\r\n--%s--\r\n" % boundary).encode()
        return eu._request("POST", "files/in", headers={"Content-Type": "multipart/form-data; boundary=" + boundary}, data=body).status
    c.check("set up: the file /in/a.txt", upload("a.txt") == 201)

    pull_site = [{"tag": "PARTNER-IN", "outbound": False, "site": SITE}]
    ids["ar"] = make_sub("an Advanced Routing subscription on /inbox with the pull site", sub_body(APP, "/inbox", transferConfigurations=pull_site))
    ids["ar2"] = make_sub("another folder of the same application, /inbox2", sub_body(APP, "/inbox2", transferConfigurations=pull_site))
    ids["basic"] = make_sub("a Basic subscription on /basic", dict(sub_body(APP_B, "/basic"), type="Basic"))
    ids["bare"] = make_sub("a sacrificial subscription with no pull site, /bare", sub_body(APP, "/bare"))
    duplicate = admin.post("subscriptions", sub_body(APP, "/inbox"))
    c.check("a second subscription on the same application and folder is 400 \"unique anchor\"",
            duplicate.status == 400 and "unique anchor" in duplicate.text, duplicate.text[:200])
    expected = {"/inbox", "/inbox2", "/basic", "/bare"}
    c.check("the list of the account shows all four subscriptions",
            wait_until(lambda: {s["folder"] for s in subs_of()} == expected), sorted(s["folder"] for s in subs_of()))
    # the filters on the list: exact account and application, a * only in the folder
    c.check("account= is exact: capitals and a wildcard find nothing",
            not subs_of(ACCOUNT.upper()) and not subs_of(ACCOUNT[:-2] + "*"))
    c.check("application= is exact too: capitals and a wildcard find nothing",
            not subs_of(application=APP.upper()) and not subs_of(application=APP[:-2] + "*"))
    c.check("folder= takes a *", {s["folder"] for s in subs_of(folder="/inbox*")} == {"/inbox", "/inbox2"})
    wrong = admin.get("subscriptions", params={"account": ACCOUNT, "limit": -1})
    c.check("limit=-1 is 400", wrong.status == 400, wrong.status)
    c.check("a type that does not exist finds nothing, with no error", not subs_of(type="nope"))
    c.check("a Basic subscription on a Basic application reads back as Basic", read(ids["basic"]).get("type") == "Basic")
    typed = admin.post("subscriptions", dict(sub_body(APP, "/wrongtype"), type="Basic"))
    if typed.status == 201:
        c.check("a body that says Basic for an Advanced Routing application is created as the application's type",
                read(typed.headers.get("Location", "").rsplit("/", 1)[-1]).get("type") == "AdvancedRouting")
        admin.delete("subscriptions/" + typed.headers.get("Location", "").rsplit("/", 1)[-1])
    else:
        c.check("a body with the wrong type for its application is created or refused", False, typed.text[:200])

    saved = read(ids["ar"])
    c.check("the subscription reads back with its pull site and a generated id",
            [t.get("site") for t in saved.get("transferConfigurations", [])] == [SITE] and saved.get("id") == ids["ar"])

    with runner.real_credentials(BASH, config):
        # ---- 05 HEAD
        out = script("05.subscriptions_id_HEAD.sh", [ACCOUNT, APP, "/inbox"])
        c.check("05 the subscription exists, and the id printed is its own", ", exists, id %s." % ids["ar"] in out, out[-200:])
        out = script("05.subscriptions_id_HEAD.sh", [ACCOUNT, APP, "/inbox2"])
        c.check("05 the other folder of the application is told apart", "id %s." % ids["ar2"] in out and ids["ar"] != ids["ar2"], out[-200:])
        out = script("05.subscriptions_id_HEAD.sh", [ACCOUNT, APP, "/inbox*"], expect_rc=1, retry=False)
        c.check("05 a wildcard is not a folder: nothing found", "Found 0 subscriptions" in out, out[-200:])
        out = script("05.subscriptions_id_HEAD.sh", [ACCOUNT, APP, "/nope"], expect_rc=1, retry=False)
        c.check("05 a folder that matches nothing is refused, with the count", "Found 0 subscriptions" in out, out[-200:])
        out = script("05.subscriptions_id_HEAD.sh", [ACCOUNT, APP.upper(), "/inbox"], expect_rc=1, retry=False)
        c.check("05 the application name is exact, with case", "Found 0 subscriptions" in out, out[-200:])
        out = script("05.subscriptions_id_HEAD.sh", ["example_subs_nobody", APP, "/inbox"], expect_rc=1, retry=False)
        c.check("05 an account that does not exist has no such subscription", "Found 0 subscriptions" in out, out[-200:])
        head, gone = admin.head("subscriptions/" + ids["ar"]), admin.head("subscriptions/nosuchid")
        c.check("HEAD answers 200 for a subscription and 404 for an id that is not one", head.status == 200 and gone.status == 404, (head.status, gone.status))

        # ---- 06 GET
        out = script("06.subscriptions_id_GET.sh", [ACCOUNT, APP, "/inbox"])
        c.check("06 prints the type and the pull site",
                "  type:              AdvancedRouting" in out and "  pull sites:        %s" % SITE in out, out[-500:])
        c.check("06 reads only some fields with fields=", '{"type":"AdvancedRouting","id":"%s","folder":"/inbox"}' % ids["ar"] in out
                or ('"id":"%s"' % ids["ar"] in out and '"folder":"/inbox"' in out and '"fileRetentionPeriod":null' in out), out[-250:])
        out = script("06.subscriptions_id_GET.sh", [ACCOUNT, APP_B, "/basic"])
        c.check("06 a Basic subscription is read the same way, with no pull site", "  type:              Basic" in out and "  pull sites:        -" in out, out[-400:])
        script("06.subscriptions_id_GET.sh", [ACCOUNT, APP, "/nope"], expect_rc=1, retry=False)
        unknown = admin.get("subscriptions/nosuchid")
        c.check("an unknown id is a JSON 404 that names it", unknown.status == 404 and "Subscription with id nosuchid not found" in unknown.text, unknown.text[:200])
        raw = admin.get("subscriptions/" + ids["ar"], params={"type": "Basic"})
        c.check("type=Basic on an Advanced Routing subscription is ignored: it is answered", raw.status == 200 and raw.json().get("type") == "AdvancedRouting", raw.text[:200])
        some = admin.get("subscriptions/" + ids["ar"], params={"fields": "folder"})
        c.check("fields= keeps the field named, and type", some.status == 200 and set(some.json()) == {"type", "folder"}, some.text[:200])

        # ---- 07 PUT
        c.check("set up: a flow attribute, so that a PUT can be seen to keep it",
                admin.patch("subscriptions/" + ids["ar"], [{"op": "add", "path": "/flowAttributes/userVars.example_kept", "value": "k"}]).status == 204)
        before = read(ids["ar"])
        out = script("07.subscriptions_id_PUT.sh", [ACCOUNT, APP, "/inbox", "3"])
        after = read(ids["ar"])
        c.check("07 prints the value before (not set), and the limit is now 3",
                "maxParallelSitPulls of the subscription is now (not set)." in out and after.get("maxParallelSitPulls") == 3, out[-300:])
        changed = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
        c.check("07 nothing else changed: the pull site, its id and the flow attribute stay", changed == {"maxParallelSitPulls"}, changed)
        out = script("07.subscriptions_id_PUT.sh", [ACCOUNT, APP, "/inbox", "0"])
        c.check("07 0 is a value too (no limit), and the value before is printed",
                "is now 3." in out and read(ids["ar"]).get("maxParallelSitPulls") == 0, out[-200:])
        script("07.subscriptions_id_PUT.sh", [ACCOUNT, APP, "/inbox2", "5"])
        c.check("07 the other folder's subscription is the one changed, this one's is not",
                read(ids["ar2"]).get("maxParallelSitPulls") == 5 and read(ids["ar"]).get("maxParallelSitPulls") == 0)
        script("07.subscriptions_id_PUT.sh", [ACCOUNT, APP_B, "/basic", "1"])
        c.check("07 a Basic subscription is replaced the same way", read(ids["basic"]).get("maxParallelSitPulls") == 1)
        before = read(ids["ar"])
        script("07.subscriptions_id_PUT.sh", [ACCOUNT, APP, "/nope"], expect_rc=1, retry=False)
        script("07.subscriptions_id_PUT.sh", [ACCOUNT, APP, "/inbox", "-1"], expect_rc=2)
        script("07.subscriptions_id_PUT.sh", [ACCOUNT, APP, "/inbox", "abc"], expect_rc=2)
        script("07.subscriptions_id_PUT.sh", [ACCOUNT, APP], expect_rc=2)
        c.check("07 the refusals changed nothing", read(ids["ar"]) == before)

        # what 07 guards against, on the sacrificial subscription: a PUT of a fragment
        sacrifice = read(ids["ar2"])
        fragment = admin.put("subscriptions/" + ids["ar2"], sub_body(APP, "/inbox2"))
        left_over = read(ids["ar2"])
        c.check("a raw PUT of a fragment answers 204 ...", fragment.status == 204, fragment.text[:200])
        c.check("... and silently drops the pull site and the limit it left out",
                left_over.get("transferConfigurations") == [] and left_over.get("maxParallelSitPulls") is None
                and [t.get("site") for t in sacrifice.get("transferConfigurations", [])] == [SITE],
                (left_over.get("transferConfigurations"), left_over.get("maxParallelSitPulls")))
        whole = {k: v for k, v in sacrifice.items() if k != "metadata"}
        r = admin.put("subscriptions/" + ids["ar2"], dict(whole, transferConfigurations=[{"tag": "PARTNER-IN", "outbound": False, "site": SITE}]))
        c.check("a transfer configuration sent without its id is stored with a new one",
                r.status == 204 and [t.get("id") for t in read(ids["ar2"]).get("transferConfigurations", [])] not in ([], [t["id"] for t in sacrifice["transferConfigurations"]]),
                (r.status, read(ids["ar2"]).get("transferConfigurations")))
        stale = admin.put("subscriptions/" + ids["ar2"], whole)
        c.check("a body that still names the old id of a transfer configuration is 400 (it does not exist any more)",
                stale.status == 400 and "does not exists" in stale.text, (stale.status, stale.text[:200]))
        whole = {k: v for k, v in read(ids["ar2"]).items() if k != "metadata"}
        notype = {k: v for k, v in whole.items() if k != "type"}
        r = admin.put("subscriptions/" + ids["ar2"], notype)
        c.check("a PUT with no type is 400", r.status == 400, (r.status, r.text[:200]))
        r = admin.put("subscriptions/" + ids["ar2"], dict(whole, type="Basic"))
        c.check("a PUT with another type is 400", r.status == 400, (r.status, r.text[:200]))
        r = admin.put("subscriptions/" + ids["ar2"], dict(whole, application=APP_B))
        c.check("a PUT with another application is 204 and the application does not change",
                r.status == 204 and read(ids["ar2"]).get("application") == APP, (r.status, read(ids["ar2"]).get("application")))
        r = admin.put("subscriptions/" + ids["ar2"], dict(whole, account="example_subs_nobody", transferConfigurations=[]))
        c.check("a PUT with an account that does not exist is 404", r.status == 404, (r.status, r.text[:200]))
        r = admin.put("subscriptions/" + ids["ar2"], dict(whole, account="example_subs_nobody"))
        c.check("... but with a transfer configuration in the body it is a bare 403 \"unable to comply\" (nothing changes)",
                r.status == 403 and read(ids["ar2"]).get("account") == ACCOUNT, (r.status, r.text[:200]))
        r = admin.put("subscriptions/nosuchid", whole)
        c.check("a PUT on an unknown id is 400 (not the 404 the reference lists)", r.status == 400 and "not found" in r.text, (r.status, r.text[:200]))
        r = admin.put("subscriptions/" + ids["ar2"], dict(whole, fileRetentionPeriod=5, transferConfigurations=[]))
        c.check("a retention with no pull site is 400", r.status == 400 and "transfer site" in r.text, (r.status, r.text[:200]))
        r = admin.put("subscriptions/" + ids["ar2"], dict(whole, maxParallelSitPulls=-1))
        c.check("a negative maxParallelSitPulls is 400", r.status == 400, (r.status, r.text[:200]))
        r = admin.put("subscriptions/" + ids["ar2"], dict(whole, flowAttributes={"example_nokey": "v"}))
        c.check("a flow attribute key without userVars. is 400", r.status == 400 and "userVars." in r.text, (r.status, r.text[:200]))
        admin.put("subscriptions/" + ids["ar2"], whole)

        # ---- 08 PATCH
        before = read(ids["ar"])
        out = script("08.subscriptions_id_PATCH.sh", [ACCOUNT, APP, "/inbox", "first"])
        after = read(ids["ar"])
        c.check("08 prints the attribute before (kept from before, not the new one), and now it is set",
                "The flow attribute userVars.example_note is now (not set)." in out
                and after.get("flowAttributes", {}).get("userVars.example_note") == "first", out[-300:])
        c.check("08 the flow attribute set before is still there", after.get("flowAttributes", {}).get("userVars.example_kept") == "k")
        changed = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
        c.check("08 nothing else changed", changed == {"flowAttributes"}, changed)
        out = script("08.subscriptions_id_PATCH.sh", [ACCOUNT, APP, "/inbox", "second"])
        c.check("08 add overwrites a value that is set, and prints the one before",
                "is now first." in out and read(ids["ar"]).get("flowAttributes", {}).get("userVars.example_note") == "second", out[-300:])
        script("08.subscriptions_id_PATCH.sh", [ACCOUNT, APP, "/inbox"])
        c.check("08 the default value is example", read(ids["ar"]).get("flowAttributes", {}).get("userVars.example_note") == "example")
        before = read(ids["ar"])
        script("08.subscriptions_id_PATCH.sh", [ACCOUNT, APP, "/inbox", " "], expect_rc=2)
        script("08.subscriptions_id_PATCH.sh", [ACCOUNT, APP], expect_rc=2)
        script("08.subscriptions_id_PATCH.sh", [ACCOUNT, APP, "/nope"], expect_rc=1, retry=False)
        c.check("08 the refusals changed nothing", read(ids["ar"]) == before)
        r = admin.patch("subscriptions/" + ids["ar"], [{"op": "add", "path": "/flowAttributes/userVars.example_note", "value": ""}])
        c.check("a blank value is 400", r.status == 400 and "empty" in r.text, (r.status, r.text[:200]))
        r = admin.patch("subscriptions/" + ids["ar"], [{"op": "replace", "path": "/flowAttributes/userVars.example_missing", "value": "v"}])
        c.check("replace of a flow attribute that is not there is 400 Missing field", r.status == 400 and "Missing field" in r.text, (r.status, r.text[:200]))
        r = admin.patch("subscriptions/" + ids["ar"], [{"op": "replace", "path": "/type", "value": "Basic"}])
        c.check("the type is read only in a patch, 400", r.status == 400, (r.status, r.text[:200]))
        r = admin.patch("subscriptions/" + ids["ar"], [{"op": "replace", "path": "/id", "value": "x"}])
        c.check("replace of /id is 204 and changes nothing", r.status == 204 and read(ids["ar"]).get("id") == ids["ar"], r.status)
        r = admin.patch("subscriptions/nosuchid", [])
        c.check("a patch of an unknown id is a JSON 404", r.status == 404, (r.status, r.text[:200]))
        r = admin.patch("subscriptions/" + ids["ar"], [{"op": "remove", "path": "/flowAttributes/userVars.example_note"}])
        c.check("remove deletes a flow attribute", r.status == 204 and "userVars.example_note" not in read(ids["ar"]).get("flowAttributes", {}), r.status)
        admin.patch("subscriptions/" + ids["ar"], [{"op": "remove", "path": "/flowAttributes/userVars.example_kept"}])

        # ---- 09 Pull
        inbox = lambda: eu.list_folder("inbox")  # noqa: E731
        c.check("the folder of a subscription is not made by the POST: /inbox is not in the home folder yet", inbox() is None, inbox())
        eu.logout()
        eu.login()
        c.check("the account's next login makes it, empty", wait_until(lambda: inbox() == []), inbox())
        out = script("09.subscriptions_id_operations_POST_pull.sh", [ACCOUNT, APP, "/inbox"])
        c.check("09 the pull is accepted (HTTP 202), and the operationIndex is printed",
                "HTTP 202" in out and "operationIndex: " in out, out[-300:])
        c.check("09 the file arrives in the subscription folder", wait_until(lambda: inbox() == ["a.txt"]), inbox())
        time.sleep(3)
        c.check("09 and stays on the partner (a pull copies)", eu.list_folder("in") == ["a.txt"], eu.list_folder("in"))
        out = script("09.subscriptions_id_operations_POST_pull.sh", [ACCOUNT, APP, "/inbox", "example_subs_nosite"], expect_rc=1)
        c.check("09 a site that does not exist is refused (406), the answer shown", "HTTP 406" in out and "was not found" in out, out[-300:])
        out = script("09.subscriptions_id_operations_POST_pull.sh", [ACCOUNT, APP, "/bare"], expect_rc=1)
        c.check("09 a subscription with no pull site says so, and sends nothing", "has no pull site" in out and "HTTP" not in out, out[-300:])
        out = script("09.subscriptions_id_operations_POST_pull.sh", [ACCOUNT, APP, "/bare", SITE])
        c.check("09 the site can be given: a subscription with no pull site of its own pulls with it", "HTTP 202" in out, out[-300:])
        raw = admin.post("subscriptions/%s/operations" % ids["ar"], None, params={"operation": "Pull"})
        c.check("a Pull with no body is refused (403)", raw.status == 403, (raw.status, raw.text[:200]))
        raw = admin.post("subscriptions/%s/operations" % ids["bare"], {"type": "pull"}, params={"operation": "Pull"})
        c.check("a Pull with no site and no pull site is 400", raw.status == 400 and "No transfer configuration" in raw.text, (raw.status, raw.text[:200]))
        raw = admin.post("subscriptions/%s/operations" % ids["ar"], {"type": "pull", "site": SITE}, params={"operation": "pull"})
        c.check("the operation name is case sensitive: pull is 404", raw.status == 404, (raw.status, raw.text[:200]))
        raw = admin.post("subscriptions/%s/operations" % ids["ar"], {"type": "pull", "site": SITE, "fileRetentionPeriod": 99999}, params={"operation": "Pull"})
        c.check("a retention over 36500 is 400", raw.status == 400, (raw.status, raw.text[:200]))
        raw = admin.post("subscriptions/nosuchid/operations", {"type": "pull", "site": SITE}, params={"operation": "Pull"})
        c.check("an unknown subscription id is 404", raw.status == 404, (raw.status, raw.text[:200]))

        # the pull history
        time.sleep(3)
        eu.delete_file("inbox/a.txt")
        for leftover in (eu.list_folder("inbox") or []):
            eu.delete_file("inbox/" + leftover)
        c.check("set up: the folder /inbox is empty again", wait_until(lambda: inbox() == []), inbox())
        whole = {k: v for k, v in read(ids["ar"]).items() if k != "metadata"}
        r = admin.put("subscriptions/" + ids["ar"], dict(whole, fileRetentionPeriod=5))
        c.check("set up: the subscription keeps its pull history for 5 days (the pull site is SSH)",
                r.status == 204 and read(ids["ar"]).get("fileRetentionPeriod") == 5, (r.status, r.text[:200]))
        script("09.subscriptions_id_operations_POST_pull.sh", [ACCOUNT, APP, "/inbox"])
        c.check("09 with a history, the first pull fetches the file", wait_until(lambda: inbox() == ["a.txt"]), inbox())
        time.sleep(5)  # the history is written after the file has arrived
        eu.delete_file("inbox/a.txt")
        c.check("set up: the pulled file is deleted from the folder", wait_until(lambda: inbox() == []), inbox())
        script("09.subscriptions_id_operations_POST_pull.sh", [ACCOUNT, APP, "/inbox"])
        time.sleep(10)
        c.check("09 with a history, a file already pulled is not pulled again, though it is gone from the folder", inbox() == [], inbox())

        # ---- 10 ClearPullHistory
        out = script("10.subscriptions_id_operations_POST_clearPullHistory.sh", [ACCOUNT, APP, "/inbox"])
        c.check("10 the clearing is accepted (HTTP 202) and says so", "HTTP 202" in out and "Clear pull history" in out and ids["ar"] in out, out[-300:])
        time.sleep(3)
        script("09.subscriptions_id_operations_POST_pull.sh", [ACCOUNT, APP, "/inbox"])
        c.check("10 after the history is cleared, the next pull fetches the file again", wait_until(lambda: inbox() == ["a.txt"]), inbox())
        out = script("10.subscriptions_id_operations_POST_clearPullHistory.sh", [ACCOUNT, APP_B, "/basic"])
        c.check("10 on a subscription with no history it is accepted as well", "HTTP 202" in out, out[-300:])
        script("10.subscriptions_id_operations_POST_clearPullHistory.sh", [ACCOUNT, APP, "/nope"], expect_rc=1, retry=False)
        script("10.subscriptions_id_operations_POST_clearPullHistory.sh", [ACCOUNT, APP], expect_rc=2)
        raw = admin.post("subscriptions/%s/operations" % ids["ar"], {"type": "clearPullHistory", "fileRetentionPeriod": 99999}, params={"operation": "ClearPullHistory"})
        c.check("a retention over 36500 in the body is 400", raw.status == 400, (raw.status, raw.text[:200]))
        raw = admin.post("subscriptions/%s/operations" % ids["ar"], None, params={"operation": "clearPullHistory"})
        c.check("the operation name is case sensitive here too", raw.status == 404, (raw.status, raw.text[:200]))
        raw = admin.post("subscriptions/%s/operations" % ids["ar"], None, params={"operation": "Nope"})
        c.check("an operation that does not exist is 404", raw.status == 404, (raw.status, raw.text[:200]))

        # ---- 11 Purge
        before = read(ids["ar"])
        names = folder_names(eu)
        c.check("11 /inbox and /inbox2 are in the home folder before the purge", {"inbox", "inbox2"} <= set(names or []), names)
        out = script("11.subscriptions_id_operations_POST_purge.sh", [ACCOUNT, APP, "/inbox"])
        c.check("11 the purge answers 204", "HTTP 204" in out, out[-200:])
        c.check("11 the whole folder is gone from the home folder, not only the file",
                wait_until(lambda: "inbox" not in (folder_names(eu) or ["inbox"])), folder_names(eu))
        c.check("11 the other folder of the application is not touched", "inbox2" in (folder_names(eu) or []), folder_names(eu))
        c.check("11 the subscription stays, unchanged", admin.head("subscriptions/" + ids["ar"]).status == 200 and read(ids["ar"]) == before)
        script("11.subscriptions_id_operations_POST_purge.sh", [ACCOUNT, APP, "/nope"], expect_rc=1, retry=False)
        script("11.subscriptions_id_operations_POST_purge.sh", [ACCOUNT], expect_rc=2)
        raw = admin.post("subscriptions/%s/operations" % ids["ar"], None, params={"operation": "purge"})
        c.check("the operation name is case sensitive: purge is 404", raw.status == 404, (raw.status, raw.text[:200]))
        script("10.subscriptions_id_operations_POST_clearPullHistory.sh", [ACCOUNT, APP, "/inbox"])
        time.sleep(3)
        script("09.subscriptions_id_operations_POST_pull.sh", [ACCOUNT, APP, "/inbox"])
        c.check("after a purge the next pull makes the folder again and fills it", wait_until(lambda: inbox() == ["a.txt"], 40), inbox())

        # ---- 12 POST types
        out = script("12.subscriptions_POST_types.sh", [ACCOUNT])
        c.check("12 prints the new subscription's id four times", out.count("New subscription ID: ") == 4 and out.count("HTTP 201") == 8, out[-600:])
        expected_types = {"Basic": "/example_Basic", "HumanSystem": "/example_HumanSystem", "MBFT": "/example_MBFT", "StandardRouter": "/example_StandardRouter"}
        for kind, folder in expected_types.items():
            sub = None

            def got(kind=kind, folder=folder):
                global sub
                sub = find(TYPE_APPS[kind], folder)
                return sub is not None
            c.check("12 the %s subscription is there, of that type" % kind, wait_until(got), sorted(s["folder"] for s in subs_of()))
            if sub:
                full = read(sub["id"])
                c.check("12 %s: type, account and application" % kind,
                        (full.get("type"), full.get("account"), full.get("application")) == (kind, ACCOUNT, TYPE_APPS[kind]), full.get("type"))
                if kind == "StandardRouter":
                    c.check("12 the StandardRouter one has its subscriberID", full.get("subscriberID") == "EXAMPLE_SUBSCRIBER", full.get("subscriberID"))
                if kind == "HumanSystem":
                    c.check("12 the HumanSystem one has its rule",
                            full.get("rules") == [{"enabled": True, "recipientPattern": "*", "fileFilterPattern": "*.txt", "targetFolder": "/example_targets"}],
                            full.get("rules"))
        c.check("12 the applications are of the types named", all((admin.get("applications/" + a).json() or {}).get("type") == k for k, a in TYPE_APPS.items()))
        c.check("12 the folders of the four subscriptions are not made by the POST ...",
                not [f for f in expected_types.values() if f.strip("/") in (folder_names(eu) or [])], folder_names(eu))
        eu.logout()
        eu.login()
        c.check("12 ... they are made at the account's next login",
                wait_until(lambda: all(f.strip("/") in (folder_names(eu) or []) for f in expected_types.values())), folder_names(eu))
        out = script("12.subscriptions_POST_types.sh", [ACCOUNT], expect_rc=1)
        c.check("12 run again: every application is refused (it exists) and every subscription too (unique anchor)",
                out.count("unique anchor") == 4 and out.count("application with this name already exists") == 4, out[-800:])
        c.check("12 and nothing was added", len([s for s in subs_of() if s["folder"].startswith("/example_")]) == 4)
        none = admin.post("subscriptions", dict(sub_body(TYPE_APPS["StandardRouter"], "/example_sr_other"), type="StandardRouter"))
        c.check("a StandardRouter subscription with no subscriberID is 400", none.status == 400 and "subscriberID" in none.text, (none.status, none.text[:200]))
        inuse = admin.delete("applications/" + TYPE_APPS["Basic"])
        c.check("an application that has a subscription cannot be deleted (400)", inuse.status == 400 and "active subscriptions" in inuse.text, (inuse.status, inuse.text[:200]))

        # ---- 13 DELETE types
        out = script("13.subscriptions_id_DELETE_types.sh", [ACCOUNT])
        c.check("13 prints HTTP 204 for each subscription and each application", out.count("HTTP 204") == 8, out[-600:])
        c.check("13 the four subscriptions are gone", wait_until(lambda: not [s for s in subs_of() if s["folder"].startswith("/example_")]),
                sorted(s["folder"] for s in subs_of()))
        c.check("13 purge=true took their folders out of the home folder",
                wait_until(lambda: not [n for n in (folder_names(eu) or []) if n.startswith("example_")]), folder_names(eu))
        c.check("13 the four applications are gone", not [a for a in TYPE_APPS.values() if admin.exists("applications/" + a)])
        c.check("13 the other subscriptions of the account are untouched", {s["folder"] for s in subs_of()} == expected)
        out = script("13.subscriptions_id_DELETE_types.sh", [ACCOUNT])
        c.check("13 run again: nothing is found, nothing fails (the applications answer 404)", out.count("none deleted") == 4 and "HTTP 404" in out, out[-500:])

    # DELETE without purge keeps the folder
    plain = make_sub("a subscription on /plain, to delete without purge", dict(sub_body(APP_B, "/plain"), type="Basic"))
    eu.logout()
    eu.login()
    c.check("the folder /plain is made at the next login", wait_until(lambda: "plain" in (folder_names(eu) or [])), folder_names(eu))
    c.check("DELETE without purge answers 204", admin.delete("subscriptions/" + plain).status == 204)
    c.check("and leaves the folder in the home folder", "plain" in (folder_names(eu) or []), folder_names(eu))
finally:
    if eu:
        for name in ("in", "inbox", "inbox2", "bare", "basic", "plain"):
            for leftover in (eu.list_folder(name) or []):
                eu.delete_file("%s/%s" % (name, leftover))
        left = folder_names(eu)
        eu.logout()
    for s in subs_of():
        admin.delete("subscriptions/" + s["id"])
    for a in (APP, APP_B) + tuple(TYPE_APPS.values()):
        admin.delete("applications/" + a)
    for s in (admin.get("sites", params={"account": ACCOUNT}).json() or {}).get("result", []):
        admin.delete("sites/" + s["id"])
    admin.delete("accounts/" + ACCOUNT)
    c.check("nothing is left behind: no subscription, application, site or account",
            wait_until(lambda: not subs_of()) and not [a for a in (APP, APP_B) + tuple(TYPE_APPS.values()) if admin.exists("applications/" + a)]
            and not admin.get("sites", params={"name": "example_subs_*"}).json().get("result") and not admin.exists("accounts/" + ACCOUNT))
    c.check("the subscription count is as before",
            wait_until(lambda: (admin.get("subscriptions", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount") == subs_before),
            (admin.get("subscriptions", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount"))
    if left is not None:
        c.info("the home folder %s stays on the lab's disk, with its folders (an account's home folder is not deleted with it): %s" % (ACCOUNT, left))
    admin.logout()

sys.exit(c.done())
