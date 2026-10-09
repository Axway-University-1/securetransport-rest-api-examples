#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 06.TransferSites examples 05 to
11 (HEAD, GET one, PUT, PATCH, the connection test of a saved and of a new site,
and the remote folder listing) against throwaway sites of two throwaway
accounts, and reads each effect back through the API.

The sites point at the lab's own servers (SSH, FTP, and the EndUser HTTPS API),
logging in as the throwaway account, so every test can succeed; and at stand-ins
on this machine (a JunkServer, a closed port) so that it can fail:

  - 05/06 find a site by account and name; the name filter ignores case and
    takes a *, so a site named in another case, a longer name and the same name
    on another account are all told apart (the exact name is what counts);
  - 07 sends the whole site back with one field changed: nothing else moves
    and the saved password still works; a raw PUT of a fragment, made once on a
    sacrificial site, silently resets what it leaves out;
  - 08 changes the download folder and nothing else;
  - 09 tests a saved site by its id, with no login in the request, over SSH,
    FTP and HTTP; a wrong saved password, a wrong password given in the
    environment, a partner that is not what it says and a closed port fail
    (exit 1), and what the environment gives wins over what was saved;
  - 10 tests a site that is not saved, and creates nothing;
  - 11 lists the download folder and the upload folder of an SSH, an FTP and an
    HTTP site, with and without the folders, and reports a folder that is not
    there. It shows that leaving folderToList out lists the UPLOAD folder.

The list of sites is not trusted to answer completely at the first read: a
script is run again, a few times, when its lookup found nothing for a site
that is known to exist, and every read through the API waits for the answer
it expects.

Needs --write and st_allow_writes="yes". Needs st_callback_host for the
stand-ins (those parts are left out, with a note, without it). Refuses to start
when an example_sites_* site exists. The two accounts get a new name and user id
on every run. Removes the sites, the files it uploaded and both accounts in a
finally block, and checks that nothing is left. "The site count is as before"
is the whole server's count, so a site made or removed by somebody else while
it runs fails it: run it again.
"""
import contextlib
import os
import socket
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import dummy_servers  # noqa: E402
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the sites examples for real")

c = st_client.Checker("Sites, run for real from Admin/API 2.0/bash/06.TransferSites (05 to 11)")
BASH = runner.path("Admin", "API 2.0", "bash")
FOLDER = os.path.join(BASH, "06.TransferSites")
SUFFIX = harness.suffix()
ACCOUNT, OTHER = "example_sites_user_" + SUFFIX, "example_sites_other_" + SUFFIX
PULL, UPPER, FTP, HTTP, WRONG, JUNK, CLOSED = ("example_sites_pull", "EXAMPLE_SITES_PULL", "example_sites_ftp", "example_sites_http",
                                               "example_sites_wrongpw", "example_sites_junk", "example_sites_closed")
PASSWORD = harness.new_password()
HOST = config["st_server"]
CALLBACK = config.get("st_callback_host", "")
ENDUSER_PORT = harness.ports(config).enduser


# When a lookup found no site that is known to exist (retry=True: the list is not always complete), the example
# is run again, up to five times. The password given as an argument is left out of the name of the check.
script = harness.bind_script(c, FOLDER, timeout=120, tail=400, retry_text="Found 0 sites named", hide=(PASSWORD,))


def sites_of(account):
    response = admin.get("sites", params={"account": account})
    return (response.json() or {}).get("result", []) if response.status == 200 else []


def find(account, name):
    found = [s for s in sites_of(account) if s["name"] == name]
    return found[0] if len(found) == 1 else None


def read(site_id):
    response = admin.get("sites/" + site_id)
    return response.json() if response.status == 200 else {}


def make_site(label, body):
    response = admin.post("sites", body)
    c.check("set up: " + label, response.status == 201, response.text[:300])
    return response.headers.get("Location", "").rsplit("/", 1)[-1]


def ssh_site(name, account=ACCOUNT, password=PASSWORD, port=None, host=None, **more):
    body = {"type": "ssh", "protocol": "ssh", "name": name, "account": account, "host": host or HOST, "port": str(port or ssh_port),
            "userName": account, "usePassword": True, "password": password, "transferType": "partner",
            "downloadFolder": "/in", "downloadPattern": "*", "uploadFolder": "/out", "maxConcurrentConnection": 4,
            "postTransmissionActions": {"doAsIn": "${stenv.target}_IN"}}
    body.update(more)
    return body


def upload(client, folder, filename, content):
    boundary = "----example_sites"
    body = ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n\r\n" % (boundary, filename)).encode() \
        + content + ("\r\n--%s--\r\n" % boundary).encode()
    return client._request("POST", "files/" + folder, headers={"Content-Type": "multipart/form-data; boundary=" + boundary}, data=body)


def raw_test(body, params=None):
    response = admin.post("sites/operations", body, params=dict({"operation": "testConnection"}, **(params or {})))
    return response, (response.json() if response.status == 200 else {})


admin = harness.connect(config, c, mock="the bundled mock does not implement /sites or the protocol servers")
if admin.get("sites", params={"name": "example_sites_*"}).json().get("result"):
    c.check("no example_sites_* site exists yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

ports = harness.ports(config, admin)
daemons = admin.get("daemons").json()
if not ports.ftp or daemons.get("sshStatus") != "Running" or daemons.get("ftpStatus") != "Running":
    c.info("the SSH and FTP daemons must be running: this check logs in to both")
    admin.logout()
    sys.exit(c.done())
ssh_port, ftp_port = ports.ssh, ports.ftp

sites_before = (admin.get("sites", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount")
ids = {}
eu = None
uploaded = []
accounts = contextlib.ExitStack()
try:
    for account in (ACCOUNT, OTHER):
        accounts.enter_context(harness.throwaway_account(admin, c, config, name=account, password=PASSWORD))
    eu = st_client.EndUserClient(HOST, ENDUSER_PORT, ACCOUNT, PASSWORD)
    eu.login()
    for folder in ("in", "out", "in/sub"):
        # a fresh home folder can refuse the first folder for a moment: try again
        made = [None]

        def create(folder=folder):
            made[0] = eu.create_folder(folder)
            return made[0].status == 201
        c.check("set up: the folder /" + folder, harness.wait_until(create, 15), (made[0].status, made[0].text[:200]))
    for folder, name, content in (("in", "i1.txt", b"one"), ("in", "i2.dat", b"twotwo"), ("out", "o1.txt", b"o")):
        status = upload(eu, folder, name, content).status
        c.check("set up: the file /%s/%s" % (folder, name), status == 201, status)
        uploaded.append("%s/%s" % (folder, name))

    ids["pull"] = make_site("the SSH site " + PULL, ssh_site(PULL))
    ids["upper"] = make_site("an SSH site named in capitals, " + UPPER, ssh_site(UPPER, uploadFolder="/out2", downloadFolder="/in2"))
    ids["other"] = make_site("a site of the same name on another account", ssh_site(PULL, OTHER, downloadFolder="/other"))
    ids["ftp"] = make_site("the FTP site", {"type": "ftp", "protocol": "ftp", "name": FTP, "account": ACCOUNT, "host": HOST, "port": str(ftp_port),
                                            "userName": ACCOUNT, "usePassword": True, "password": PASSWORD, "downloadFolder": "/in",
                                            "downloadPattern": "*", "uploadFolder": "/out", "transferType": "partner"})
    ids["http"] = make_site("the HTTP site, on the EndUser API", {"type": "http", "protocol": "http", "name": HTTP, "account": ACCOUNT, "host": HOST,
                                                                  "port": str(ENDUSER_PORT), "isSecure": True, "userName": ACCOUNT, "usePassword": True,
                                                                  "password": PASSWORD, "downloadFolder": "/in", "downloadPattern": "*", "uploadFolder": "/out"})
    ids["wrong"] = make_site("an SSH site with the wrong password", ssh_site(WRONG, password="Wrong-" + PASSWORD))
    free = socket.socket()
    free.bind(("127.0.0.1", 0))
    closed_port = free.getsockname()[1]
    free.close()
    ids["closed"] = make_site("an SSH site whose port nobody listens on", ssh_site(CLOSED, port=closed_port))
    expected = {PULL, UPPER, FTP, HTTP, WRONG, CLOSED}
    c.check("the list of the account shows all of its sites", harness.wait_until(lambda: {s["name"] for s in sites_of(ACCOUNT)} >= expected),
            sorted(s["name"] for s in sites_of(ACCOUNT)))
    c.check("and of the other account its one", harness.wait_until(lambda: [s["name"] for s in sites_of(OTHER)] == [PULL]), [s["name"] for s in sites_of(OTHER)])
    duplicate = admin.post("sites", ssh_site(PULL))
    c.check("a second site of the same name on the same account is 409", duplicate.status == 409 and "already exist" in duplicate.text, duplicate.text[:200])

    saved = read(ids["pull"])
    c.check("the site reads back with the password encrypted, never the one sent",
            str(saved.get("password", "")).startswith("{AES128}") and PASSWORD not in str(saved), saved.get("password"))

    with runner.real_credentials(BASH, config):
        # ---- 05 HEAD
        out = script("05.sites_id_HEAD.sh", [ACCOUNT, PULL])
        c.check("05 the site exists, and the id printed is its own", "The site %s of %s exists, id %s." % (PULL, ACCOUNT, ids["pull"]) in out, out[-200:])
        out = script("05.sites_id_HEAD.sh", [ACCOUNT, UPPER])
        c.check("05 the site named in capitals is told apart from it (the name filter ignores case)",
                "id %s." % ids["upper"] in out and ids["upper"] != ids["pull"], out[-200:])
        out = script("05.sites_id_HEAD.sh", [OTHER, PULL])
        c.check("05 the same name on the other account is that account's own site", "id %s." % ids["other"] in out, out[-200:])
        out = script("05.sites_id_HEAD.sh", [ACCOUNT, "example_sites_pul*"], expect_rc=1, retry=False)
        c.check("05 a wildcard is not a name: nothing found", "Found 0 sites" in out, out[-200:])
        out = script("05.sites_id_HEAD.sh", [ACCOUNT, "example_sites_nope"], expect_rc=1, retry=False)
        c.check("05 a name that matches nothing is refused, with the count", "Found 0 sites" in out, out[-200:])
        out = script("05.sites_id_HEAD.sh", ["example_sites_nobody", PULL], expect_rc=1, retry=False)
        c.check("05 an account that does not exist has no such site", "Found 0 sites" in out, out[-200:])
        head = admin.head("sites/" + ids["pull"])
        gone = admin.head("sites/nosuchid")
        c.check("HEAD answers 200 for a site and 404 for an id that is not one", head.status == 200 and gone.status == 404, (head.status, gone.status))

        # ---- 06 GET
        out = script("06.sites_id_GET.sh", [ACCOUNT, PULL])
        c.check("06 prints the type, the partner and the folders",
                all(t in out for t in ("  type:             ssh", "  partner:          %s:%s" % (HOST, ssh_port),
                                       "  download folder:  /in", "  upload folder:    /out", "  max connections:  4")), out[-600:])
        c.check("06 prints the password as stored (encrypted), never in clear",
                "  password:         " + saved["password"] in out and PASSWORD not in out, out[-300:])
        c.check("06 reads only some fields with fields=",
                '{"type":"ssh","name":"%s","host":"%s","port":"%s"}' % (PULL, HOST, ssh_port) in out, out[-200:])
        out = script("06.sites_id_GET.sh", [ACCOUNT, FTP])
        c.check("06 an FTP site is read the same way", "  type:             ftp" in out and "%s:%s" % (HOST, ftp_port) in out, out[-400:])
        out = script("06.sites_id_GET.sh", [ACCOUNT, "example_sites_nope"], expect_rc=1, retry=False)
        raw = admin.get("sites/" + ids["pull"], params={"type": "http"})
        c.check("type=http on an SSH site is ignored: the site is answered", raw.status == 200 and raw.json().get("type") == "ssh", raw.text[:200])
        unknown = admin.get("sites/nosuchid")
        c.check("an unknown id is a JSON 404 that names it", unknown.status == 404 and "Site with id nosuchid not found" in unknown.text, unknown.text[:200])

        # ---- 07 PUT
        before = read(ids["pull"])
        out = script("07.sites_id_PUT.sh", [ACCOUNT, PULL, "7"])
        after = read(ids["pull"])
        c.check("07 prints the value before, and the limit is now 7",
                "maxConcurrentConnection of %s is now 4." % PULL in out and after.get("maxConcurrentConnection") == 7, out[-300:])
        changed = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
        c.check("07 nothing else changed, the password included", changed == {"maxConcurrentConnection"}, changed)
        out = script("09.sites_operations_POST_test.sh", [ACCOUNT, PULL], env={"SITE_PASSWORD": ""})
        c.check("07 the saved password still works after the PUT (the connection test succeeds)",
                "  authentication:  success" in out, out[-300:])
        script("07.sites_id_PUT.sh", [ACCOUNT, PULL, "4"])
        c.check("07 putting the value back gives the site exactly as it was", read(ids["pull"]) == before)
        script("07.sites_id_PUT.sh", [ACCOUNT, PULL, "0"])
        c.check("07 0 is a value too", read(ids["pull"]).get("maxConcurrentConnection") == 0)
        script("07.sites_id_PUT.sh", [ACCOUNT, PULL, "4"])
        script("07.sites_id_PUT.sh", [ACCOUNT, FTP, "3"])
        c.check("07 an FTP site is replaced the same way", read(ids["ftp"]).get("maxConcurrentConnection") == 3)
        script("07.sites_id_PUT.sh", [ACCOUNT, FTP, "0"])
        before_other = read(ids["other"])
        script("07.sites_id_PUT.sh", [OTHER, PULL, "5"])
        c.check("07 the other account's site of the same name is the one changed, this account's is not",
                read(ids["other"]).get("maxConcurrentConnection") == 5 and read(ids["pull"]).get("maxConcurrentConnection") == 4)
        script("07.sites_id_PUT.sh", [OTHER, PULL, str(before_other.get("maxConcurrentConnection"))])
        c.check("07 and it is put back as it was", read(ids["other"]) == before_other)
        script("07.sites_id_PUT.sh", [ACCOUNT, "example_sites_nope"], expect_rc=1, retry=False)
        script("07.sites_id_PUT.sh", [ACCOUNT, PULL, "70000"], expect_rc=2)
        script("07.sites_id_PUT.sh", [ACCOUNT], expect_rc=2)
        c.check("07 the refusals changed nothing", read(ids["pull"]) == before)

        # what 07 guards against, on the sacrificial site: a PUT of a fragment
        sacrifice = read(ids["upper"])
        fragment = admin.put("sites/" + ids["upper"], {"type": "ssh", "protocol": "ssh", "name": UPPER, "account": ACCOUNT, "host": HOST,
                                                         "port": str(ssh_port), "userName": ACCOUNT, "usePassword": True, "password": PASSWORD,
                                                         "transferType": "partner"})
        left = read(ids["upper"])
        c.check("a raw PUT of a fragment answers 204 ...", fragment.status == 204, fragment.text[:200])
        c.check("... and silently resets what it left out (folders, limit, renaming)",
                left.get("downloadFolder") is None and left.get("uploadFolder") is None and left.get("maxConcurrentConnection") == 0
                and (left.get("postTransmissionActions") or {}).get("doAsIn") is None
                and (sacrifice.get("downloadFolder"), sacrifice.get("uploadFolder")) == ("/in2", "/out2"),
                (left.get("downloadFolder"), left.get("uploadFolder"), left.get("maxConcurrentConnection")))
        nopass = dict(sacrifice)
        nopass.pop("metadata", None)
        nopass.pop("password", None)
        refused = admin.put("sites/" + ids["upper"], nopass)
        c.check("a PUT with no password is 400 \"Specify password\"", refused.status == 400 and "Specify password" in refused.text, refused.text[:200])
        moved = dict(sacrifice)
        moved.pop("metadata", None)
        moved["account"] = OTHER
        r = admin.put("sites/" + ids["upper"], moved)
        c.check("a PUT with another account is 204 and the account does not change", r.status == 204 and read(ids["upper"]).get("account") == ACCOUNT,
                (r.status, read(ids["upper"]).get("account")))
        retype = dict(sacrifice)
        retype.pop("metadata", None)
        retype["type"], retype["protocol"] = "ftp", "ftp"
        r = admin.put("sites/" + ids["upper"], retype)
        c.check("a PUT with another type is refused, 400", r.status == 400, (r.status, r.text[:200]))
        whole = dict(sacrifice)
        whole.pop("metadata", None)
        r = admin.put("sites/nosuchid", whole)
        c.check("a PUT on an unknown id is 404", r.status == 404, r.status)

        # ---- 08 PATCH
        before = read(ids["pull"])
        out = script("08.sites_id_PATCH.sh", [ACCOUNT, PULL, "/archive"])
        after = read(ids["pull"])
        c.check("08 prints the folder before, and the download folder is now /archive",
                "The download folder of %s is now /in." % PULL in out and after.get("downloadFolder") == "/archive", out[-300:])
        changed = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
        c.check("08 nothing else changed", changed == {"downloadFolder"}, changed)
        out = script("08.sites_id_PATCH.sh", [ACCOUNT, PULL])
        c.check("08 /inbox by default, and the folder before is /archive",
                "is now /archive." in out and read(ids["pull"]).get("downloadFolder") == "/inbox", out[-200:])
        script("08.sites_id_PATCH.sh", [ACCOUNT, PULL, "/in"])
        c.check("08 putting the folder back gives the site exactly as it was", read(ids["pull"]) == before)
        script("08.sites_id_PATCH.sh", [ACCOUNT, FTP, "/in"])
        script("08.sites_id_PATCH.sh", [ACCOUNT, "example_sites_nope"], expect_rc=1, retry=False)
        script("08.sites_id_PATCH.sh", [ACCOUNT], expect_rc=2)
        patch = lambda ops: admin.patch("sites/" + ids["pull"], ops)  # noqa: E731
        r = patch([{"op": "replace", "path": "/type", "value": "ftp"}])
        c.check("type is read only: 400", r.status == 400 and "read only or discriminator" in r.text, r.text[:200])
        r = patch([{"op": "replace", "path": "/nosuch", "value": "x"}])
        c.check("a path that does not exist is 400", r.status == 400 and "Missing field" in r.text, r.text[:200])
        r = patch([{"op": "add", "path": "/postTransmissionActions/doAsOut", "value": "${stenv.target}_OUT"}])
        c.check("add creates a nested field", r.status == 204 and read(ids["pull"])["postTransmissionActions"]["doAsOut"] == "${stenv.target}_OUT", r.text[:200])
        r = patch([{"op": "remove", "path": "/postTransmissionActions/doAsOut"}])
        c.check("remove sets it to null, it does not drop the key",
                r.status == 204 and "doAsOut" in read(ids["pull"])["postTransmissionActions"]
                and read(ids["pull"])["postTransmissionActions"]["doAsOut"] is None, r.text[:200])
        r = patch([{"op": "replace", "path": "/account", "value": OTHER}])
        c.check("replace of /account is 204 and changes nothing", r.status == 204 and read(ids["pull"]).get("account") == ACCOUNT, r.status)
        r = patch([])
        c.check("an empty patch is 204", r.status == 204, r.status)
        r = admin.patch("sites/nosuchid", [{"op": "replace", "path": "/name", "value": "x"}])
        c.check("a PATCH on an unknown id is 404", r.status == 404, r.status)
        c.check("the raw patches left the site as it was", read(ids["pull"]) == before)

        # ---- 09 test a saved site
        out = script("09.sites_operations_POST_test.sh", [ACCOUNT, PULL], env={"SITE_PASSWORD": ""})
        c.check("09 an SSH site: connection and login succeed, with no login in the request",
                "  connection:      success" in out and "  authentication:  success" in out, out[-300:])
        out = script("09.sites_operations_POST_test.sh", [ACCOUNT, FTP], env={"SITE_PASSWORD": ""})
        c.check("09 an FTP site", "  authentication:  success" in out, out[-300:])
        out = script("09.sites_operations_POST_test.sh", [ACCOUNT, HTTP], env={"SITE_PASSWORD": ""})
        c.check("09 an HTTP site", "  authentication:  success" in out, out[-300:])
        # A wrong SSH password counts as two failed logins (password, then keyboard-interactive), and three in a
        # row lock the account: so every failure is followed by a login that works, which resets the count
        out = script("09.sites_operations_POST_test.sh", [ACCOUNT, WRONG], expect_rc=1, env={"SITE_PASSWORD": ""})
        c.check("09 a saved wrong password: the connection works, the login fails, and it says why",
                "  connection:      success" in out and "  authentication:  failed" in out and "authentication failed" in out.lower(), out[-400:])
        out = script("09.sites_operations_POST_test.sh", [ACCOUNT, WRONG], env={"SITE_PASSWORD": PASSWORD})
        c.check("09 the right password in the environment wins over the saved wrong one, and resets the failures",
                "  authentication:  success" in out, out[-300:])
        out = script("09.sites_operations_POST_test.sh", [ACCOUNT, PULL], expect_rc=1, env={"SITE_PASSWORD": "Wrong-" + PASSWORD})
        c.check("09 a wrong password in the environment wins over the saved right one", "  authentication:  failed" in out, out[-300:])
        out = script("09.sites_operations_POST_test.sh", [ACCOUNT, PULL], env={"SITE_PASSWORD": ""})
        c.check("09 the saved password works again, and the account is not locked", "  authentication:  success" in out
                and admin.get("accounts/" + ACCOUNT, params={"type": "user"}).json()["user"]["locked"] is False, out[-300:])
        c.check("09 the test changed nothing: the wrong site is still saved with its wrong password",
                read(ids["wrong"]).get("password") != read(ids["pull"]).get("password"))
        out = script("09.sites_operations_POST_test.sh", [ACCOUNT, CLOSED], expect_rc=1, env={"SITE_PASSWORD": ""})
        c.check("09 a port nobody listens on: the connection fails, \"Connection refused\"",
                "  connection:      failed" in out and "Connection refused" in out, out[-300:])
        script("09.sites_operations_POST_test.sh", [ACCOUNT, "example_sites_nope"], expect_rc=1, retry=False)
        if CALLBACK:
            with dummy_servers.JunkServer() as junk:
                ids["junk"] = make_site("an SSH site whose partner is a JunkServer", ssh_site(JUNK, host=CALLBACK, port=junk.port))
                c.check("the site is listed", harness.wait_until(lambda: find(ACCOUNT, JUNK) is not None))
                out = script("09.sites_operations_POST_test.sh", [ACCOUNT, JUNK], expect_rc=1, env={"SITE_PASSWORD": ""})
                c.check("09 a partner that is not an SSH server: the connection fails with the server's reason, and the stand-in saw the call",
                        "  connection:      failed" in out and "negotiate" in out and junk.connections >= 1, (out[-300:], junk.connections))
        else:
            c.info("st_callback_host is not set: the stand-in partner is left out")

        # ---- 10 test a site that is not saved
        count = len(sites_of(ACCOUNT))
        env = {"SITE_PASSWORD": PASSWORD}
        out = script("10.sites_operations_POST_test_new.sh", [ACCOUNT, "ssh", HOST, str(ssh_port), ACCOUNT], env=env)
        c.check("10 an SSH partner that is not saved: connection and login succeed",
                "  connection:      success" in out and "  authentication:  success" in out, out[-300:])
        out = script("10.sites_operations_POST_test_new.sh", [ACCOUNT, "ftp", HOST, str(ftp_port), ACCOUNT], env=env)
        c.check("10 an FTP partner", "  authentication:  success" in out, out[-300:])
        out = script("10.sites_operations_POST_test_new.sh", [ACCOUNT, "http", HOST, str(ENDUSER_PORT), ACCOUNT, "true"], env=env)
        c.check("10 an HTTP partner over TLS (SECURE true)", "  authentication:  success" in out, out[-300:])
        out = script("10.sites_operations_POST_test_new.sh", [ACCOUNT, "http", HOST, str(ENDUSER_PORT), ACCOUNT, "false"], expect_rc=1, env=env)
        c.check("10 the same partner without TLS fails", "  connection:      failed" in out or "  authentication:  failed" in out, out[-300:])
        out = script("10.sites_operations_POST_test_new.sh", [ACCOUNT, "ssh", HOST, str(ssh_port), ACCOUNT], expect_rc=1,
                     env={"SITE_PASSWORD": "Wrong-" + PASSWORD})
        c.check("10 a wrong password: the connection works, the login fails", "  connection:      success" in out and "  authentication:  failed" in out, out[-300:])
        out = script("10.sites_operations_POST_test_new.sh", [ACCOUNT, "ftp", HOST, str(ftp_port), ACCOUNT], env=env)
        c.check("10 the right one works again (the failed SSH login counted twice against the account)", "  authentication:  success" in out, out[-300:])
        out = script("10.sites_operations_POST_test_new.sh", [ACCOUNT, "ssh", HOST, str(closed_port), ACCOUNT], expect_rc=1, env=env)
        c.check("10 a closed port: Connection refused", "Connection refused" in out, out[-300:])
        out = script("10.sites_operations_POST_test_new.sh", ["example_sites_nobody", "ssh", HOST, str(ssh_port), ACCOUNT], expect_rc=1, env=env)
        c.check("10 an account that does not exist is refused by the server (400)", "HTTP 400" in out, out[-300:])
        script("10.sites_operations_POST_test_new.sh", [ACCOUNT, "smb"], expect_rc=2, env=env)
        script("10.sites_operations_POST_test_new.sh", [ACCOUNT], expect_rc=2, env={"SITE_PASSWORD": ""})
        c.check("10 created nothing: no site example_untested, the account's sites as before",
                find(ACCOUNT, "example_untested") is None and len(sites_of(ACCOUNT)) == count, (count, len(sites_of(ACCOUNT))))

        # A wrong SSH password is two failed logins, and the second wrong test locks the account (on the
        # other account, which nothing else here uses)
        env_wrong = {"SITE_PASSWORD": "Wrong-" + PASSWORD}
        script("10.sites_operations_POST_test_new.sh", [OTHER, "ssh", HOST, str(ssh_port), OTHER], expect_rc=1, env=env_wrong)
        user = admin.get("accounts/" + OTHER, params={"type": "user"}).json()["user"]
        c.check("a wrong SSH password counts as two failed logins (the second is keyboard-interactive)",
                user["failedAuthAttempts"] == 2 and user["locked"] is False, (user["failedAuthAttempts"], user["locked"]))
        script("10.sites_operations_POST_test_new.sh", [OTHER, "ssh", HOST, str(ssh_port), OTHER], expect_rc=1, env=env_wrong)
        user = admin.get("accounts/" + OTHER, params={"type": "user"}).json()["user"]
        c.check("and a second wrong test LOCKS the account (failedAuthMaximum %s)" % user["failedAuthMaximum"],
                user["locked"] is True, (user["failedAuthAttempts"], user["locked"]))
        out = script("10.sites_operations_POST_test_new.sh", [OTHER, "ssh", HOST, str(ssh_port), OTHER], expect_rc=1, env={"SITE_PASSWORD": PASSWORD})
        c.check("a locked account refuses even the right password", "  authentication:  failed" in out, out[-300:])

        # ---- 11 list a remote folder
        def listed(out):
            return sorted(line.split()[0] for line in out.splitlines() if line.startswith("    "))
        out = script("11.sites_operations_POST_list.sh", [ACCOUNT, PULL])
        c.check("11 the download folder of the SSH site: its two files and the folder inside it",
                "  folder:      /in" in out and listed(out) == ["i1.txt", "i2.dat", "sub"] and "  entries:     3 of 3" in out, out[-500:])
        out = script("11.sites_operations_POST_list.sh", [ACCOUNT, PULL, "downloadFolder", "20", "false"])
        c.check("11 FOLDERS false leaves the folder out", listed(out) == ["i1.txt", "i2.dat"], out[-400:])
        out = script("11.sites_operations_POST_list.sh", [ACCOUNT, PULL, "uploadFolder"])
        c.check("11 the upload folder, with the entry's size and permissions", listed(out) == ["o1.txt"] and "o1.txt  1.00 bytes  -rw" in out, out[-400:])
        out = script("11.sites_operations_POST_list.sh", [ACCOUNT, PULL, "downloadFolder", "1"])
        c.check("11 a limit of 1 lists one entry", len(listed(out)) == 1 and "  entries:     1 of " in out, out[-400:])
        out = script("11.sites_operations_POST_list.sh", [ACCOUNT, FTP])
        c.check("11 an FTP site lists its download folder too", "  folder:      /in" in out and {"i1.txt", "i2.dat"} <= set(listed(out)), out[-400:])
        out = script("11.sites_operations_POST_list.sh", [ACCOUNT, HTTP, "uploadFolder"])
        c.check("11 an HTTP site lists its upload folder", "  folder:      /out" in out and listed(out) == ["o1.txt"], out[-400:])
        script("08.sites_id_PATCH.sh", [ACCOUNT, PULL, "/nodir"])
        out = script("11.sites_operations_POST_list.sh", [ACCOUNT, PULL], expect_rc=1)
        c.check("11 a folder that is not there: 200, an empty list and the reason",
                "  entries:     0 of 0" in out and "No such file" in out, out[-400:])
        script("08.sites_id_PATCH.sh", [ACCOUNT, PULL, "/in"])
        out = script("11.sites_operations_POST_list.sh", [ACCOUNT, WRONG], expect_rc=1)
        c.check("11 a site whose login fails is not listed: the connection is reported failed, with the reason",
                "  connection:  failed" in out and "Authentication failure" in out and "o1.txt" not in out and "i1.txt" not in out, out[-400:])
        out = script("11.sites_operations_POST_list.sh", [ACCOUNT, PULL])
        c.check("11 and the account still logs in (one failed SSH login does not lock it)", "i1.txt" in out, out[-300:])
        script("11.sites_operations_POST_list.sh", [ACCOUNT, PULL, "sideFolder"], expect_rc=2)
        script("11.sites_operations_POST_list.sh", [ACCOUNT, PULL, "downloadFolder", "many"], expect_rc=2)
        script("11.sites_operations_POST_list.sh", [ACCOUNT, "example_sites_nope"], expect_rc=1, retry=False)

    # What the notes of 11 say, with the raw calls (the body names the site by id)
    body = {"id": ids["pull"], "name": PULL, "host": HOST, "port": str(ssh_port), "protocol": "ssh", "account": ACCOUNT}

    def raw_list(params):
        response = admin.post("sites/operations", body, params=dict({"operation": "listRemoteFolder"}, **params))
        return response.json() if response.status == 200 else {}
    left_out = raw_list({})
    asked = raw_list({"folderToList": "downloadFolder"})
    c.info("folderToList left out lists %s (the reference says the download folder, /in); asked for downloadFolder: %s"
           % (left_out.get("remoteFolder"), asked.get("remoteFolder")))
    c.check("asked for the download folder, the download folder is listed", asked.get("remoteFolder") == "/in", asked.get("remoteFolder"))
    default_names = [e["fileName"] for e in left_out.get("result", [])]
    folders_on = [e["fileName"] for e in raw_list({"folderToList": "downloadFolder", "includesFolderNamesInResult": "true"}).get("result", [])]
    folders_off = [e["fileName"] for e in raw_list({"folderToList": "downloadFolder", "includesFolderNamesInResult": "false"}).get("result", [])]
    folders_default = [e["fileName"] for e in raw_list({"folderToList": "downloadFolder"}).get("result", [])]
    c.info("includesFolderNamesInResult left out lists %s; true %s; false %s" % (folders_default, folders_on, folders_off))
    c.check("includesFolderNamesInResult=true lists the folder, false does not", "sub" in folders_on and "sub" not in folders_off, (folders_on, folders_off))
    del default_names
    r = admin.post("sites/operations", body, params={"operation": "nope"})
    c.check("an operation that does not exist is 400", r.status == 400 and "testConnection or listRemoteFolder" in r.text, r.text[:200])
    r = admin.post("sites/operations", {"id": "nosuchid", "name": "x", "host": HOST, "port": "1", "protocol": "ssh"}, params={"operation": "testConnection"})
    c.check("a test with an unknown id is 404", r.status == 404, r.status)
    r, answer = raw_test({"id": ids["pull"], "name": PULL, "host": HOST, "port": str(ssh_port), "protocol": "ssh", "account": ACCOUNT})
    c.check("a test with only the identifying fields uses the saved login: success", answer.get("authenticationStatus") == "success", r.text[:200])
    r, answer = raw_test({"id": ids["pull"], "name": PULL, "host": "nonexistent.invalid", "port": str(ssh_port), "protocol": "ssh", "account": ACCOUNT})
    c.check("a host in the body wins over the saved one: Unknown site host", "Unknown site host" in str(answer.get("errorDetails")), r.text[:200])
    r, answer = raw_test({"id": ids["pull"], "name": PULL, "host": HOST, "port": str(ssh_port), "protocol": "zzz", "account": ACCOUNT})
    c.check("the protocol in the body is ignored: the saved site's is used", answer.get("authenticationStatus") == "success", r.text[:200])
finally:
    if eu:
        for path in reversed(uploaded):
            eu.delete_file(path)
        for folder in ("in/sub", "in", "out"):
            eu.delete_file(folder)
        listing = eu.list_files()
        left = [f.get("fileName") for f in (listing.json() or {}).get("files", [])] if listing.status == 200 else ["(not readable)"]
        eu.logout()
    for account in (ACCOUNT, OTHER):
        for s in sites_of(account):
            admin.delete("sites/" + s["id"])
    accounts.close()
    c.check("nothing is left behind: no example_sites_* site, no account",
            not admin.get("sites", params={"name": "example_sites_*"}).json().get("result")
            and not admin.exists("accounts/" + ACCOUNT) and not admin.exists("accounts/" + OTHER))
    c.check("the site count is as before",
            harness.wait_until(lambda: (admin.get("sites", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount") == sites_before),
            (admin.get("sites", params={"limit": 1, "fields": "id"}).json() or {}).get("resultSet", {}).get("totalCount"))
    if eu:
        c.check("the files and folders the check made are gone from the home folder", left == [], left)
    admin.logout()

sys.exit(c.done())
