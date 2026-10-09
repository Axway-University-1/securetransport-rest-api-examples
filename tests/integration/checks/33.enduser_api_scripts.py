#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the EndUser API examples added from the API
reference - 03.Myself, 04.FileOperations, 05.Transfers, 06.ServerTime and
02.Files 09 to 15 - as a throwaway end user, and checks each one's effect
through the API, not only its exit code.

Two throwaway accounts: <prefix>euapi, the user the examples run as, and
<prefix>euapi2, its partner. The partner is the user a folder is shared with,
and the other end of two SSH sites the admin API gives the user - a pull site
reading the partner's /out, and a push site writing to its /in - so the user's
own pull and push examples have something to work with.

Covered, each checked independently:
  03.Myself       account, password expiry, a password change and back, the
                  secret questions (or a clean "service not enabled"), the
                  address book, an entry by id
  02.Files        an upload into a folder with Content-MD5, its metadata, the
                  listing parameters and a glob, rename by PUT and by PATCH,
                  share and unshare
  04.FileOperations  MD5Calc against the local file, an operation's state,
                  a chunked upload, a multipart content upload, a cancel
  05.Transfers    a pull and its summary, a push, a folder monitor run, the
                  log and one transfer's details
  06.ServerTime   the server's clock

Not run, and why:
  04/05.myself_password_POST_requestLink / _reset  send and need a real
                  password reset email
  07.transfers_id_operations_POST_verifymdn  needs an AS2 transfer

The examples reuse the session in EndUser/API 2.0/bash/myCookie.jar, which
01.Authenticate/01.myself_POST.sh writes. A cookie jar already there is put
back afterwards, as is set_variables.local.sh.

Needs --write and st_allow_writes="yes".
"""
import base64
import hashlib
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the EndUser API examples for real")

c = st_client.Checker("EndUser API examples from the API reference, run for real")

PREFIX = config.get("st_object_prefix") or "ZZTEST_"
USER = PREFIX + "euapi"
PARTNER = PREFIX + "euapi2"
PARTNER_EMAIL = PARTNER.lower() + "@example.com"
PASSWORD = harness.new_password()
NEW_PASSWORD = "Bz" + PASSWORD[2:]
ENDUSER_PORT = harness.ports(config).enduser
SSH_HOST = config.get("st_ssh_host") or config["st_server"]

TREE = runner.path("EndUser", "API 2.0", "bash")
COOKIE = os.path.join(TREE, "myCookie.jar")


def script(rel, args=None, expect=(0,)):
    """Run one EndUser example, check its exit code, and return (the exit code, its output)."""
    out = harness.run_script(c, TREE, rel, args, expect, timeout=120, label="{name} exits {rc}")
    return out.returncode, out


def eu(account=USER, password=PASSWORD):
    return st_client.EndUserClient(config["st_server"], ENDUSER_PORT, account, password)


def upload_into(client, folder, name, data):
    """A multipart upload into a folder: POST /files/{folder}."""
    boundary = "----zztest"
    body = (("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n\r\n" % (boundary, name)).encode()
            + data + ("\r\n--%s--\r\n" % boundary).encode())
    return client._request("POST", "files/" + folder,
                           headers={"Content-Type": "multipart/form-data; boundary=" + boundary}, data=body)


def metadata(client, path):
    return (client._request("GET", "files/%s?metadata=true" % path).json() or {}).get("self", {})


admin = harness.connect(config, c, mock="the bundled mock does not implement the EndUser API; run this against a real server")
SSH_PORT = harness.ports(config, admin).ssh

taken = [n for n in (USER, PARTNER) if admin.exists("accounts/" + n)]
c.check("none of the throwaway accounts exist yet", not taken, taken)
if taken:
    admin.logout()
    sys.exit(c.done())

made = []
work = harness.scratch("zztest_euapi_")
cookie_backup = open(COOKIE, "rb").read() if os.path.exists(COOKIE) else None
eu_config = dict(config, st_port=ENDUSER_PORT, st_user=USER, st_password=PASSWORD)

try:
    # -- the two accounts, the user's two sites, the partner's folders ----------
    for name in (USER, PARTNER):
        response = admin.post("accounts", {
            "name": name, "type": "user", "uid": "1050", "gid": "1050", "homeFolder": "/home/" + name,
            "transfersWebServiceAllowed": True, "contact": {"email": name.lower() + "@example.com"},
            "user": {"name": name, "passwordCredentials": {"password": PASSWORD}}})
        c.check('created the throwaway account "%s"' % name, response.status == 201, response.text[:200])
        if response.status != 201:
            raise SystemExit
        made.append(name)
    for site, extra in (("euapi_pull", {"downloadFolder": "/out", "downloadPatternType": "glob", "downloadPattern": "*.txt"}),
                        ("euapi_push", {"uploadFolder": "/in"})):
        response = admin.post("sites", dict({"type": "ssh", "protocol": "ssh", "name": site, "account": USER,
                                             "host": SSH_HOST, "port": SSH_PORT, "userName": PARTNER,
                                             "usePassword": True, "password": PASSWORD,
                                             "transferType": "partner"}, **extra))
        c.check("the user has the SSH site %s" % site, response.status == 201, response.text[:200])
    with eu(PARTNER) as partner:
        partner.create_folder("out")
        partner.create_folder("in")
        c.check("the partner has a file to pull", upload_into(partner, "out", "to_pull.txt", b"pull me\n").status == 201)
    with eu() as user:
        for folder in ("dir1", "landing", "fm_from", "fm_to"):
            user.create_folder(folder)
        upload_into(user, "fm_from", "fm.txt", b"folder monitor\n")
        user.upload("/to_push.txt", b"push me\n", "to_push.txt")

    local_file = os.path.join(work, "sample.txt")
    with open(local_file, "wb") as f:
        f.write(b"EndUser API sample, line by line.\n" * 80)
    local_md5 = base64.b64encode(hashlib.md5(open(local_file, "rb").read()).digest()).decode()

    with runner.real_credentials(TREE, eu_config):
        script("01.Authenticate/01.myself_POST.sh")

        # -- 03.Myself ---------------------------------------------------------
        rc, out = script("03.Myself/01.myself_GET.sh")
        c.check("01.myself_GET.sh prints the account", "account           %s (user)" % USER in out, out[-300:])
        script("03.Myself/02.myself_passwordExpired_GET.sh")

        rc, out = script("03.Myself/03.myself_password_POST_change.sh", [NEW_PASSWORD])
        with eu(USER, NEW_PASSWORD) as check:
            c.check("the new password logs in", True)
        with runner.real_credentials(TREE, dict(eu_config, st_password=NEW_PASSWORD)):
            script("03.Myself/03.myself_password_POST_change.sh", [PASSWORD])
        with eu() as check:
            c.check("and the original one again, after changing it back", True)

        rc, out = script("03.Myself/06.secretQuestions_GET.sh", expect=(0, 3))
        if rc == 3:
            c.info("the secret question service is not enabled on this server: 06, 07 and 08 "
                   "were checked to say so cleanly")
            script("03.Myself/07.myself_secretQuestion_GET.sh", expect=(3,))
            script("03.Myself/08.myself_secretQuestion_PUT.sh", ["Q", "A"], expect=(3,))
        else:
            question = re.findall(r"^  (.+)$", out, re.M)[0]
            script("03.Myself/08.myself_secretQuestion_PUT.sh", [question, "zztest answer"])
            rc, out = script("03.Myself/07.myself_secretQuestion_GET.sh")
            c.check("07 reads back the question 08 set", question in out, out[-200:])

        rc, out = script("03.Myself/09.myself_addressBook_GET.sh", [PARTNER.lower()[:8] + "*"])
        match = re.search(r"^  (\S+)  \S+  .*%s" % re.escape(PARTNER_EMAIL), out, re.M | re.I)
        c.check("09 finds the partner in the address book", match is not None, out[-400:])
        if match:
            rc, out = script("03.Myself/10.myself_addressBook_id_GET.sh", [match.group(1)])
            c.check("10 reads the partner's entry by its id", PARTNER_EMAIL in out.lower() and "HTTP 200" in out, out[-300:])

        # -- 02.Files 09 to 15 ----------------------------------------------------
        rc, out = script("02.Files/11.files_filepath_POST_md5.sh", [local_file, "dir1"])
        with eu() as user:
            c.check("11 put sample.txt in dir1, intact",
                    user.download("dir1/sample.txt").body == open(local_file, "rb").read())
        rc, out = script("02.Files/10.files_filepath_GET_metadata.sh", ["dir1/sample.txt"])
        c.check("10 prints the file's size", "%d bytes" % os.path.getsize(local_file) in out, out[-300:])
        rc, out = script("02.Files/09.files_GET_query.sh", ["dir1", "*.txt"])
        c.check("09 lists sample.txt, and finds it by the glob", out.count("sample.txt") >= 2, out[-400:])

        script("02.Files/12.files_filepath_PUT_rename.sh", ["dir1/sample.txt", "dir1/renamed.txt"])
        with eu() as user:
            c.check("12 renamed it", user.list_folder("dir1") == ["renamed.txt"], user.list_folder("dir1"))
        script("02.Files/13.files_filepath_PATCH_rename.sh", ["dir1/renamed.txt", "dir1/sample.txt"])
        with eu() as user:
            c.check("13 renamed it back", user.list_folder("dir1") == ["sample.txt"], user.list_folder("dir1"))

        script("02.Files/14.files_filepath_PATCH_share.sh", ["dir1", PARTNER_EMAIL])
        with eu() as user:
            c.check("14 shared dir1", metadata(user, "dir1").get("isShared") is True, metadata(user, "dir1"))
        script("02.Files/15.files_filepath_PATCH_unshare.sh", ["dir1"])
        with eu() as user:
            c.check("15 stopped sharing it", metadata(user, "dir1").get("isShared") is False, metadata(user, "dir1"))

        # -- 04.FileOperations -----------------------------------------------------
        rc, out = script("04.FileOperations/01.fileOperations_POST_md5calc.sh", ["dir1/sample.txt", local_file])
        c.check("01 MD5Calc matches the local file", "It matches" in out and local_md5 in out, out[-300:])
        with eu() as user:
            op = (user._request("POST", "fileOperations", {"Content-Type": "application/json"},
                                json.dumps({"operation": "MD5Calc", "filePath": "/dir1/sample.txt"}).encode()).json() or {}).get("id")
        # the operation can be read a moment after it is started: ask until the example can print it, then check it
        harness.wait_until(lambda: "MD5Calc of /dir1/sample.txt" in harness.run_script(
            c, TREE, "04.FileOperations/02.fileOperations_id_GET.sh", [op], expect_rc=None, timeout=120), 20, 2)
        rc, out = script("04.FileOperations/02.fileOperations_id_GET.sh", [op])
        c.check("02 reads the operation's state", "MD5Calc of /dir1/sample.txt" in out, out[-300:])

        script("04.FileOperations/03.fileOperations_id_PUT_chunked.sh", [local_file, "landing", "1000"])
        with eu() as user:
            c.check("03 the chunked upload is the whole file",
                    user.download("landing/sample.txt").body == open(local_file, "rb").read())
            user.delete_file("landing/sample.txt")
        script("04.FileOperations/04.fileOperations_id_POST_multipart.sh", [local_file, "fm_to"])
        with eu() as user:
            c.check("04 the multipart upload is the whole file",
                    user.download("fm_to/sample.txt").body == open(local_file, "rb").read())
            user.delete_file("fm_to/sample.txt")
        script("04.FileOperations/05.fileOperations_id_DELETE.sh")

        # -- 05.Transfers ---------------------------------------------------------
        index = "zztest-euapi-%d" % int(time.time())
        rc, out = script("05.Transfers/03.transfers_operations_POST_pull.sh", ["euapi_pull", "landing", index])
        c.check("03 the pull expected one file", "Files expected: 1" in out, out[-300:])
        # the pull is carried out a moment after it is accepted: ask until its summary counts the file, then check it
        harness.wait_until(lambda: "1 file(s): 1 successful" in harness.run_script(
            c, TREE, "05.Transfers/04.transfers_pullSummary_GET.sh", [index], expect_rc=None, timeout=120), 30, 2)
        rc, out = script("05.Transfers/04.transfers_pullSummary_GET.sh", [index])
        c.check("04 the pull summary counts it as successful", "1 file(s): 1 successful" in out, out[-200:])
        with eu() as user:
            c.check("and it is in landing", user.list_folder("landing") == ["to_pull.txt"], user.list_folder("landing"))

        script("05.Transfers/05.transfers_operations_POST_push.sh", ["euapi_push", "to_push.txt"])
        with eu(PARTNER) as partner:
            c.check("05 the push arrived in the partner's /in", partner.list_folder("in") == ["to_push.txt"],
                    partner.list_folder("in"))

        script("05.Transfers/06.transfers_operations_POST_folderMonitor.sh", ["fm_from", "fm_to", "*.txt"])
        with eu() as user:
            c.check("06 the folder monitor moved fm.txt", (user.list_folder("fm_from"), user.list_folder("fm_to")) == ([], ["fm.txt"]),
                    (user.list_folder("fm_from"), user.list_folder("fm_to")))

        rc, out = script("05.Transfers/01.transfers_GET.sh", ["5"])
        c.check("01 lists the user's transfers", "to_pull.txt" in out or "to_push.txt" in out, out[-400:])
        rc, out = script("05.Transfers/02.transfers_id_GET.sh")
        c.check("02 reads the latest transfer's details", "In short:" in out, out[-300:])

        # -- 06.ServerTime ------------------------------------------------------------
        rc, out = script("06.ServerTime/01.serverTime_GET.sh")
        c.check("01 compares the server's clock with this machine's", "from this machine's" in out, out[-200:])

    c.info("not run: 03.Myself/04 and 05 (they need a real password reset email), and "
           "05.Transfers/07 verifymdn (it needs an AS2 transfer)")

except SystemExit:
    pass

finally:
    if cookie_backup is not None:
        with open(COOKIE, "wb") as f:
            f.write(cookie_backup)
    elif os.path.exists(COOKIE):
        os.remove(COOKIE)
    for site in (admin.get("sites", params={"account": USER}).json() or {}).get("result", []):
        admin.delete("sites/" + site["id"])
    for name in made:
        # Deleting an account leaves its files on disk, so remove them first. The
        # password may still be the new one if a step failed in between.
        for password in (PASSWORD, NEW_PASSWORD):
            try:
                with eu(name, password) as client:
                    for folder in ("dir1", "landing", "fm_from", "fm_to", "out", "in"):
                        for f in client.list_folder(folder) or []:
                            client.delete_file(folder + "/" + f)
                        client.delete_file(folder)
                    for f in client.list_folder("") or []:
                        client.delete_file(f)
                break
            except st_client.STError:
                continue
        admin.delete("accounts/" + name)
    left = [n for n in (USER, PARTNER) if admin.exists("accounts/" + n)]
    c.check("everything this check created was removed", not left, left)
    admin.logout()

sys.exit(c.done())
