#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs EndUser/UseCases 02-knowing-yourself, 03-files-and-folders,
04-larger-files and 05-checking-transfers for real (01-authentication has check 62), as a
throwaway end user account this check creates, with a password only it knows, and removes.

For each: 00.run_all.sh exits 0, and what it made on the server is gone again
afterwards: the home folder has no example_uc_* entry left, and 99.cleanup_DELETE.sh
can be run a second time with nothing to remove (exit 0). The file use cases' own
steps are checked against the server as well: a file the use case uploaded is read back
through the EndUser API by this check, not by the script.

Needs --write and st_allow_writes="yes". The end user port is the one the other
EndUser checks use (st_enduser_port, or one less than the admin port).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the EndUser use cases for real")

c = st_client.Checker("EndUser use cases 02 to 05, run for real")

ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
USE_CASES = runner.path("EndUser", "UseCases")
ACCOUNT = config.get("st_enduser_test_account", "ZZTEST_enduser") + "_uc2"
ACCOUNT_PASSWORD = harness.new_password()
ENDUSER_PORT = harness.ports(config).enduser

admin = harness.connect(config, c, mock=("the bundled mock does not implement the EndUser API on a second port; "
                                         "run this against a real server to exercise it"))
created = False
folders = ("03-files-and-folders", "04-larger-files")


def clear_local(name):
    for leftover in ("session.cookie.jar", "state.local.csrf"):
        p = os.path.join(USE_CASES, name, leftover)
        if os.path.exists(p):
            os.remove(p)


def home_entries(client):
    response = client.list_files({"showdots": "true", "limit": 100})
    return [f.get("fileName", "") for f in ((response.json() or {}).get("files", []) if response.status == 200 else [])]


try:
    if admin.exists("accounts/" + ACCOUNT):
        c.info('an account named "%s" already exists; skipping rather than reuse it' % ACCOUNT)
        admin.logout()
        sys.exit(c.done())
    response = admin.post("accounts", {
        "name": ACCOUNT, "type": "user", "uid": "1052", "gid": "1052",
        "homeFolder": "/home/" + ACCOUNT, "transfersWebServiceAllowed": True,
        "user": {"name": ACCOUNT, "passwordCredentials": {"password": ACCOUNT_PASSWORD}},
    })
    created = response.status == 201
    c.check('created a throwaway end user account "%s"' % ACCOUNT, created, response.text[:200])
    if not created:
        admin.logout()
        sys.exit(c.done())

    eu_config = dict(config, st_port=ENDUSER_PORT, st_user=ACCOUNT, st_password=ACCOUNT_PASSWORD)
    eu = st_client.EndUserClient(config["st_server"], ENDUSER_PORT, ACCOUNT, ACCOUNT_PASSWORD)
    with runner.real_credentials(ENDUSER_TREE, eu_config):
        for name in ("02-knowing-yourself", "03-files-and-folders", "04-larger-files", "05-checking-transfers"):
            r = runner.run(os.path.join(USE_CASES, name, "00.run_all.sh"), timeout=300)
            c.check("%s: 00.run_all.sh exits 0" % name, r.returncode == 0, (r.stdout + r.stderr).strip()[-400:])
            c.check("%s: it ended with the cleanup" % name, "Cleaned up." in r.stdout, r.stdout[-200:])
            r = runner.run(os.path.join(USE_CASES, name, "99.cleanup_DELETE.sh"))
            c.check("%s: 99.cleanup_DELETE.sh a second time, with nothing to remove, exits 0" % name, r.returncode == 0)
            if name in folders:
                eu.login()
                left = [e for e in home_entries(eu) if e.startswith("example_")]
                eu.logout()
                c.check("%s: nothing named example_* is left in the home folder" % name, left == [], left)

        # 03 step by step: what a file really is on the server after each step
        uc = os.path.join(USE_CASES, "03-files-and-folders")
        for step in ("01.folder_POST.sh", "02.files_POST_upload.sh"):
            r = runner.run(os.path.join(uc, step))
            c.check("03 %s exits 0" % step, r.returncode == 0, (r.stdout + r.stderr).strip()[-300:])
        eu.login()
        got = eu.download("example_uc_files/notes.txt")
        c.check("03: the uploaded file reads back through the API", got.status == 200 and "First version" in got.text, got.status)
        eu.logout()
        r = runner.run(os.path.join(uc, "01.folder_POST.sh"))
        c.check("03: creating the folder a second time says it exists and exits 0", r.returncode == 0 and "already exists" in r.stdout, r.stdout[-200:])
        r = runner.run(os.path.join(uc, "07.files_PATCH_rename.sh"))
        c.check("03: 07 renames the file (a 403 right after the upload is tried again)", r.returncode == 0 and "HTTP 204" in r.stdout, r.stdout[-300:])
        eu.login()
        c.check("03: the file is now under the new name, and the old name is gone",
                eu.download("example_uc_files/notes_renamed.txt").status == 200 and eu.download("example_uc_files/notes.txt").status == 404)
        eu.logout()
        r = runner.run(os.path.join(uc, "08.files_PATCH_rename_missing.sh"))
        c.check("03: 08 renames a name that is not there: 403, and it is not there", r.returncode == 0 and "HTTP 403" in r.stdout and "the 403 was for a file that is not there" in r.stdout, r.stdout[-300:])
        r = runner.run(os.path.join(uc, "09.files_POST_folder_in_name.sh"))
        c.check("03: 09 sends a filename with a folder in it: 201, and the file lands in the home folder", r.returncode == 0 and "landed in the home folder" in r.stdout, r.stdout[-400:])
        eu.login()
        c.check("03: 09 removed what it put in the home folder", "example_uc_landed.txt" not in home_entries(eu), home_entries(eu))
        eu.logout()
        r = runner.run(os.path.join(uc, "10.files_DELETE_file.sh"))
        c.check("03: 10 deletes the file", r.returncode == 0, r.stdout[-300:])
        r = runner.run(os.path.join(uc, "11.folder_DELETE.sh"))
        c.check("03: 11 refuses the folder with a file in it, empties it, deletes it", r.returncode == 0 and "HTTP 403" in r.stdout, r.stdout[-300:])
        runner.run(os.path.join(uc, "99.cleanup_DELETE.sh"))

        # 04 step by step: what the server holds after a refused upload, as text and binary, and out of order
        uc = os.path.join(USE_CASES, "04-larger-files")
        for step in ("01.folder_POST.sh", "02.files_POST_md5.sh"):
            r = runner.run(os.path.join(uc, step))
            c.check("04 %s exits 0" % step, r.returncode == 0, (r.stdout + r.stderr).strip()[-300:])
        r = runner.run(os.path.join(uc, "03.files_POST_md5_refused.sh"))
        c.check("04: 03 sends a wrong Content-MD5, is refused, looks, deletes, sends again and verifies",
                r.returncode == 0 and "HTTP 500" in r.stdout and "Verified:" in r.stdout, r.stdout[-600:])
        eu.login()
        c.check("04: the file of 03 is on the server after the run, whole",
                eu.download("example_uc_large/example_md5_wrong.bin").status == 200)
        eu.logout()
        r = runner.run(os.path.join(uc, "05.files_POST_text_binary.sh"))
        c.check("04: 05 shows ASCII dropping the CR and BINARY keeping it", r.returncode == 0 and "BINARY kept every byte" in r.stdout, r.stdout[-500:])
        eu.login()
        ascii_text = eu.download("example_uc_large/example_text_ascii.txt").text
        binary_text = eu.download("example_uc_large/example_text_binary.txt").text
        eu.logout()
        c.check("04: read back through the API, the ASCII file has no CR and the BINARY file has them",
                "\r" not in ascii_text and "\r" in binary_text, (ascii_text, binary_text))
        r = runner.run(os.path.join(uc, "06.fileOperations_PUT_chunked.sh"))
        c.check("04: 06 sends three pieces in order and the MD5 of the file is the local one",
                r.returncode == 0 and "Verified:" in r.stdout, r.stdout[-500:])
        r = runner.run(os.path.join(uc, "07.fileOperations_PUT_out_of_order.sh"))
        c.check("04: 07 sends the last piece first: refused, and the file is not whole",
                r.returncode == 0 and "HTTP 500" in r.stdout and "is listed" in r.stdout and "not whole" in r.stdout, r.stdout[-600:])
        r = runner.run(os.path.join(uc, "08.fileOperations_POST_multipart.sh"))
        c.check("04: 08 stores the content under the name of the local file when the form has no filename=",
                r.returncode == 0 and "the name of the operation was not used" in r.stdout, r.stdout[-500:])
        runner.run(os.path.join(uc, "99.cleanup_DELETE.sh"))

        # The home folder outlives the account: a file left in it is there for a new account with the same home folder
        eu.login()
        put = eu.upload("example_outlives.txt", b"still here\n")
        eu.logout()
        c.check("03: a file for the home-folder test is uploaded", put.status in (200, 201), put.status)
        c.check("03: the account is deleted", admin.delete("accounts/" + ACCOUNT).status == 204)
        again = admin.post("accounts", {
            "name": ACCOUNT, "type": "user", "uid": "1052", "gid": "1052",
            "homeFolder": "/home/" + ACCOUNT, "transfersWebServiceAllowed": True,
            "user": {"name": ACCOUNT, "passwordCredentials": {"password": ACCOUNT_PASSWORD}},
        })
        c.check("03: an account with the same name and home folder is made again", again.status == 201, again.text[:200])
        eu.login()
        c.check("03: the file is still in the home folder: it outlived the account", "example_outlives.txt" in home_entries(eu), home_entries(eu))
        eu.delete_file("example_outlives.txt")
        eu.logout()
finally:
    for name in ("02-knowing-yourself", "03-files-and-folders", "04-larger-files", "05-checking-transfers"):
        clear_local(name)
    if created:
        admin.delete("accounts/" + ACCOUNT)
        c.check('the throwaway account "%s" was removed' % ACCOUNT, not admin.exists("accounts/" + ACCOUNT))
    admin.logout()

sys.exit(c.done())
