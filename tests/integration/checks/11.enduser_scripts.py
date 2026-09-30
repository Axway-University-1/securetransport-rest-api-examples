#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified scripts in
EndUser/API 2.0/bash against a configured server: login, list, upload,
download, delete, and logout, then verifies every step through the EndUser
API directly, and cleans up completely.

Unlike the admin checks, this one needs no separate end user account
configured ahead of time. It creates one of its own through the admin API,
with a password only this check knows, runs the EndUser scripts as that
account, and deletes the account again at the end - the same throwaway
pattern 04.accounts_scripts.py uses for "john", just applied to the account
this whole check runs under rather than to one object inside it.

The EndUser API has no CSRF token anywhere, and no session cookie handling to
get wrong the way the admin API's cost real time earlier in this project: the
scripts send Authorization once at login and rely on the cookie jar
afterward, and EndUserClient in st_client.py does the same.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.

The end user port defaults to one less than the admin port (8444 -> 8443, or
444 -> 443, matching this project's own convention), or set st_enduser_port in
integration.conf to override it.

03.files_filepath_GET.sh downloads a file named "download_file.txt", a
different name to the "test.txt" that 04.files_filepath_POST.sh uploads - that
file is not created by anything in this folder. This check uploads it as a
fixture through EndUserClient before running 03, the same way
04.accounts_scripts.py creates a throwaway "john" account before running the
scripts that need one to already exist.

04.files_filepath_POST.sh appends a line to a real, git tracked file next to
it (test.txt) every time it runs. This check backs that file up before running
it and restores it afterward, so a test run never leaves the working tree
dirty.

Two more things confirmed while building this:
  - Deleting an account does not delete its home folder's files from disk.
    Recreating an account with the same homeFolder can inherit files an
    earlier run left there - this check now cleans up defensively at the
    start rather than assume a freshly created account is empty.
  - DELETE /files/{path} works. EndUserClient.delete_file() is what this
    check uses for its own defensive cleanup; 07.files_filepath_DELETE.sh -
    a new example added alongside this update - is the shipped script that
    now demonstrates the same call for real, deleting and re-uploading
    test.txt mid-run so the later steps that depend on it are unaffected.
Both are recorded in .claude/skills/st-api-gotchas/SKILL.md.
"""
import base64
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the EndUser scripts for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("EndUser, run for real from EndUser/API 2.0/bash")

ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
AUTH_DIR = os.path.join(ENDUSER_TREE, "01.Authenticate")
FILES_DIR = os.path.join(ENDUSER_TREE, "02.Files")

ACCOUNT = config.get("st_enduser_test_account", "ZZTEST_enduser")
ACCOUNT_PASSWORD = "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"
ENDUSER_PORT = config.get("st_enduser_port") or str(int(config["st_port"]) - 1)

admin = st_client.connect(config, c)

if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /files or a second port; "
           "run this against a real server to exercise it")
    admin.logout()
    sys.exit(c.done())

created_account = False
test_txt_backup = None
test_txt_path = os.path.join(FILES_DIR, "test.txt")
download_txt_path = os.path.join(FILES_DIR, "download_file.txt")
downloaded_dir = os.path.join(FILES_DIR, "downloaded_files")


def cleanup_local_files():
    if test_txt_backup is not None:
        with open(test_txt_path, "w") as f:
            f.write(test_txt_backup)
    elif os.path.exists(test_txt_path):
        os.remove(test_txt_path)
    if os.path.exists(download_txt_path):
        os.remove(download_txt_path)
    for i in (1, 2):
        for p in (test_txt_path + "_%d" % i,
                  os.path.join(downloaded_dir, "test.txt_%d" % i)):
            if os.path.exists(p):
                os.remove(p)


try:
    if admin.exists("accounts/" + ACCOUNT):
        c.info('an account named "%s" already exists on this server; '
               "skipping this check rather than reuse it. Delete it or "
               "change st_enduser_test_account in integration.conf."
               % ACCOUNT)
        admin.logout()
        sys.exit(c.done())

    response = admin.post("accounts", {
        "name": ACCOUNT, "type": "user", "uid": "1050", "gid": "1050",
        "homeFolder": "/home/" + ACCOUNT,
        "user": {"name": ACCOUNT, "passwordCredentials": {"password": ACCOUNT_PASSWORD}},
    })
    created_account = response.status == 201
    c.check('created a throwaway end user account "%s"' % ACCOUNT, created_account,
            response.text[:200])
    if not created_account:
        admin.logout()
        sys.exit(c.done())

    if os.path.exists(test_txt_path):
        with open(test_txt_path) as f:
            test_txt_backup = f.read()

    eu_config = dict(config)
    eu_config["st_port"] = ENDUSER_PORT
    eu_config["st_user"] = ACCOUNT
    eu_config["st_password"] = ACCOUNT_PASSWORD

    with runner.real_credentials(ENDUSER_TREE, eu_config):

        result = runner.run(os.path.join(AUTH_DIR, "01.myself_POST.sh"))
        c.check("01.myself_POST.sh runs without a shell level error", result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")
        c.check("the script reports a successful login",
                "Successfully Authenticated" in result.stdout, result.stdout[-200:])

        euclient = st_client.EndUserClient(config["st_server"], ENDUSER_PORT,
                                           ACCOUNT, ACCOUNT_PASSWORD)
        try:
            euclient.login()
        except st_client.STError as e:
            c.check("connect to the end user port", False, e)
            c.info("tried port %s (the admin port minus one, the convention "
                   "this project documents). If that is not this server's "
                   "end user port, set st_enduser_port in integration.conf."
                   % ENDUSER_PORT)
            raise SystemExit(c.done())

        try:

            # A freshly created account is not guaranteed to start with an
            # empty home folder: confirmed that deleting an account does not
            # delete its home folder's files from disk, so a later account
            # reusing the same homeFolder can inherit files an earlier test
            # run left behind. Clean up defensively rather than assume.
            listing = euclient.list_files().json() or {}
            leftover = [f.get("fileName") for f in listing.get("files", [])]
            if leftover:
                c.info("this account's home folder already had files on it "
                       "(%s), left behind by an earlier run; removing them "
                       "before this run starts" % leftover)
                for name in leftover:
                    euclient.delete_file(name)

            listing = euclient.list_files().json() or {}
            c.check("the account has no files once cleaned up",
                    not listing.get("files"), listing)

            # -- 01: list files --------------------------------------------------
            result = runner.run(os.path.join(FILES_DIR, "01.files_GET.sh"))
            c.check("01.files_GET.sh runs without a shell level error",
                    result.returncode == 0, result.stderr.strip()[-300:] if result.returncode else "")

            # -- 04: upload test.txt -----------------------------------------------
            result = runner.run(os.path.join(FILES_DIR, "04.files_filepath_POST.sh"))
            c.check("04.files_filepath_POST.sh runs without a shell level error",
                    result.returncode == 0, result.stderr.strip()[-300:] if result.returncode else "")

            listing = euclient.list_files().json() or {}
            names = {f.get("fileName") for f in listing.get("files", [])}
            c.check('"test.txt" is listed after the upload', "test.txt" in names, names)

            downloaded = euclient.download("test.txt")
            c.check("the uploaded content downloads back correctly",
                    downloaded.status == 200 and b"Append to the file" in downloaded.body,
                    downloaded.body[:100])

            # -- 07: delete test.txt, then re-upload it for the steps that need it --
            result = runner.run(os.path.join(FILES_DIR, "07.files_filepath_DELETE.sh"))
            c.check("07.files_filepath_DELETE.sh runs without a shell level error",
                    result.returncode == 0, result.stderr.strip()[-300:] if result.returncode else "")
            c.check("07.files_filepath_DELETE.sh reports success",
                    "successfully deleted" in result.stdout, result.stdout[-200:])

            listing = euclient.list_files().json() or {}
            names = {f.get("fileName") for f in listing.get("files", [])}
            c.check('"test.txt" is no longer listed after 07 deletes it',
                    "test.txt" not in names, names)

            up = euclient.upload("test.txt", b"Append to the file\n")
            c.check("test.txt re-uploaded for the remaining steps", up.status in (200, 201), up.status)

            # -- 03: download download_file.txt, uploaded here as a fixture ---------
            fixture_content = b"fixture content for 03.files_filepath_GET.sh\n"
            up = euclient.upload("download_file.txt", fixture_content)
            c.check("the download_file.txt fixture uploads", up.status in (200, 201), up.status)

            result = runner.run(os.path.join(FILES_DIR, "03.files_filepath_GET.sh"))
            c.check("03.files_filepath_GET.sh runs without a shell level error",
                    result.returncode == 0, result.stderr.strip()[-300:] if result.returncode else "")
            if os.path.exists(download_txt_path):
                with open(download_txt_path, "rb") as f:
                    written = f.read()
                c.check("the file the script wrote locally matches what was uploaded",
                        written == fixture_content, written[:100])
            else:
                c.check("03.files_filepath_GET.sh wrote the file locally", False)

            # -- 05/06: bulk upload and download, a small count ----------------------
            result = runner.run(os.path.join(FILES_DIR, "05.files_filepath_POST_v2.sh"), args=["2"])
            c.check("05.files_filepath_POST_v2.sh runs without a shell level error",
                    result.returncode == 0, result.stderr.strip()[-300:] if result.returncode else "")

            listing = euclient.list_files().json() or {}
            names = {f.get("fileName") for f in listing.get("files", [])}
            c.check("both bulk uploaded files are listed",
                    {"test.txt_1", "test.txt_2"} <= names, names)

            result = runner.run(os.path.join(FILES_DIR, "06.files_filepath_GET_v2.sh"), args=["2"])
            c.check("06.files_filepath_GET_v2.sh runs without a shell level error",
                    result.returncode == 0, result.stderr.strip()[-300:] if result.returncode else "")
            c.check("06.files_filepath_GET_v2.sh reports success",
                    "Files successfully retrieved" in result.stdout, result.stdout[-200:])

        finally:
            # euclient's session is independent of the one the bash scripts
            # keep in their own cookie jar, so it needs its own logout.
            euclient.logout()

        result = runner.run(os.path.join(AUTH_DIR, "02.myself_DELETE.sh"))
        c.check("02.myself_DELETE.sh runs without a shell level error", result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")
        c.check("the script reports a successful logout",
                "Successfully Logged out" in result.stdout, result.stdout[-200:])

finally:
    cleanup_local_files()
    if created_account:
        admin.delete("accounts/" + ACCOUNT)
        c.check('the throwaway account "%s" was removed' % ACCOUNT,
                not admin.exists("accounts/" + ACCOUNT))
    admin.logout()

c.info("%d admin API calls issued by the verification client (not counting "
       "the EndUser scripts' own curl calls)" % admin.calls)

sys.exit(c.done())
