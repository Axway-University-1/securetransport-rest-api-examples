#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs EndUser/UseCases/06-sharing-a-folder for real, with three throwaway end user accounts this
check creates and removes: an owner with an e-mail address, a collaborator with one, and an account with none.

  - 01 stops the account with no e-mail (exit 3, sharingAllowed is false), and says why;
  - 00.run_all.sh as the owner, sharing with the collaborator's address, exits 0 and cleans up;
  - step by step, what the COLLABORATOR really sees, read through the API by this check and not by the scripts:
      the folder in their root, named "<folder> (<owner e-mail>)", and its file readable;
      rights 1: an upload and a delete are refused (403);
      rights 3 (05): an upload works, a delete of their file is refused;
      rights 7 (05): an upload and a delete work;
      after 06 the folder is gone from their list, and still there for the owner;
  - 99.cleanup_DELETE.sh leaves nothing: no folder named example_uc_shared* in either home.

Needs --write and st_allow_writes="yes". The end user port is the one the other EndUser checks use.
"""
import os
import sys
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the sharing use case for real")

c = st_client.Checker("EndUser use case 06-sharing-a-folder, run for real")

ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
UC = runner.path("EndUser", "UseCases", "06-sharing-a-folder")
BASE = config.get("st_enduser_test_account", "ZZTEST_enduser") + "_shr"
OWNER, GUEST, NOMAIL = BASE + "_o", BASE + "_g", BASE + "_n"
PASSWORDS = {name: harness.new_password() for name in (OWNER, GUEST, NOMAIL)}
EMAIL = {OWNER: OWNER.lower() + "@example.com", GUEST: GUEST.lower() + "@example.com"}
ENDUSER_PORT = harness.ports(config).enduser
FOLDER = "example_uc_shared"
SHARED_NAME = "%s (%s)" % (FOLDER, EMAIL[OWNER])

admin = harness.connect(config, c, mock=("the bundled mock does not implement the EndUser API on a second port; "
                                         "run this against a real server to exercise it"))
created = []


def run(script, user, args=None):
    cfg = dict(config, st_port=ENDUSER_PORT, st_user=user, st_password=PASSWORDS[user])
    with runner.real_credentials(ENDUSER_TREE, cfg):
        return runner.run(os.path.join(UC, script), args or [], timeout=300)
COOKIE_JAR = os.path.join(ENDUSER_TREE, "myCookie.jar")


def clear_local():
    for leftover in ("session.cookie.jar", "state.local.csrf"):
        p = os.path.join(UC, leftover)
        if os.path.exists(p):
            os.remove(p)


def client(name):
    return st_client.EndUserClient(config["st_server"], ENDUSER_PORT, name, PASSWORDS[name])


def root_names(user):
    response = user.list_files({"showdots": "true"})
    return [f.get("fileName") for f in (response.json() or {}).get("files", [])] if response.status == 200 else None


try:
    uid = 1060
    for name in (OWNER, GUEST, NOMAIL):
        if admin.exists("accounts/" + name):
            c.info('an account named "%s" already exists; skipping rather than reuse it' % name)
            admin.logout()
            sys.exit(c.done())
    for name in (OWNER, GUEST, NOMAIL):
        uid += 1
        body = {"name": name, "type": "user", "uid": str(uid), "gid": str(uid), "homeFolder": "/home/" + name,
                "user": {"name": name, "passwordCredentials": {"password": PASSWORDS[name]}}}
        if name in EMAIL:
            body["contact"] = {"email": EMAIL[name]}
        response = admin.post("accounts", body)
        ok = response.status == 201
        if ok:
            created.append(name)
        c.check('created the throwaway account "%s"' % name, ok, response.text[:200])
        if not ok:
            admin.logout()
            sys.exit(c.done())

    # a home folder that an earlier crashed run left behind comes with the account name: start from nothing
    run("99.cleanup_DELETE.sh", OWNER)

    # -- an account with no e-mail address ---------------------------------------------------------------
    r = run("01.sharing_GET_myself.sh", NOMAIL)
    c.check("01 for an account with no e-mail: exit 3, and it says why",
            r.returncode == 3 and "no e-mail address" in r.stdout, (r.returncode, r.stdout[-300:]))
    c.check("and says that a session already open does not see a new address", "end the session with ./99.cleanup_DELETE.sh" in r.stdout, r.stdout[-300:])
    run("02.folder_POST.sh", NOMAIL)   # the folder has to be there: sharing a folder that is not answers 204, whoever asks
    r = run("03.folder_PATCH_share.sh", NOMAIL, [EMAIL[GUEST]])
    c.check("03 for it: refused with the 400, exit 1, and the hint", r.returncode == 1 and "Shared folders functionality is disabled" in r.stdout
            and "an account with no e-mail address" in r.stdout, (r.returncode, r.stdout[-300:]))
    # An administrator gives the account an address. The session of the use case is still open, and does not know it.
    patch = admin.patch("accounts/" + NOMAIL, [{"op": "replace", "path": "/contact/email", "value": NOMAIL.lower() + "@example.com"}])
    c.check("an administrator sets the e-mail address of the account (204)", patch.status == 204, patch.status)
    r = run("01.sharing_GET_myself.sh", NOMAIL)
    c.check("in the same session 01 still says no (exit 3): the session keeps what it started with", r.returncode == 3, (r.returncode, r.stdout[-200:]))
    run("99.cleanup_DELETE.sh", NOMAIL)
    r = run("01.sharing_GET_myself.sh", NOMAIL)
    c.check("after the session is ended and a new one begun, 01 says yes (exit 0)", r.returncode == 0 and "sharingAllowed: true" in r.stdout, (r.returncode, r.stdout[-200:]))
    run("99.cleanup_DELETE.sh", NOMAIL)
    r = run("03.folder_PATCH_share.sh", NOMAIL)
    c.check("03 with no parameters prints its usage (exit 2)", r.returncode == 2 and "Usage: ./03.folder_PATCH_share.sh EMAIL [RIGHTS]" in r.stdout, (r.returncode, r.stdout[-200:]))

    # -- the whole use case ------------------------------------------------------------------------------
    r = run("00.run_all.sh", OWNER, [EMAIL[GUEST], "read"])
    c.check("00.run_all.sh as the owner, sharing with the collaborator, exits 0", r.returncode == 0, (r.stdout + r.stderr)[-400:])
    c.check("it ended with the cleanup", "Cleaned up." in r.stdout, r.stdout[-200:])
    clear_local()

    # -- step by step, with the collaborator's own view ------------------------------------------------------
    for script, args in (("01.sharing_GET_myself.sh", []), ("02.folder_POST.sh", []), ("03.folder_PATCH_share.sh", [EMAIL[GUEST]])):
        r = run(script, OWNER, args)
        c.check("%s exits 0" % script, r.returncode == 0, (r.stdout + r.stderr)[-300:])
    guest = client(GUEST)
    guest.login()
    names = root_names(guest)
    c.check('the collaborator sees "%s" in their root' % SHARED_NAME, names is not None and SHARED_NAME in names, names)
    path = urllib.parse.quote(SHARED_NAME)
    c.check("and can read the file in it", guest._request("GET", "files/%s/notes.txt" % path).status == 200)
    c.check("rights 1: an upload is refused (403)", guest.upload_to(SHARED_NAME, "g1.txt", b"x\n").status == 403)
    c.check("rights 1: a delete is refused (403)", guest._request("DELETE", "files/%s/notes.txt" % path).status == 403)
    r = run("04.folder_GET_sharing.sh", OWNER)
    c.check("04 shows the collaborator and the rights", EMAIL[GUEST] in r.stdout and "rights:        1 (read)" in r.stdout, r.stdout[-300:])

    r = run("05.folder_PATCH_rights.sh", OWNER)
    c.check("05 with no parameter prints its usage (exit 2)", r.returncode == 2 and "Usage: ./05.folder_PATCH_rights.sh RIGHTS" in r.stdout, (r.returncode, r.stdout[-200:]))
    r = run("05.folder_PATCH_rights.sh", OWNER, ["write"])
    c.check("05 write sets the rights to 3 and reads them back", r.returncode == 0 and "Read back: 3" in r.stdout, (r.stdout + r.stderr)[-300:])
    c.check("rights write: an upload works", guest.upload_to(SHARED_NAME, "g3.txt", b"x\n").status == 201)
    c.check("rights write: a delete of their file is refused (403)", guest._request("DELETE", "files/%s/g3.txt" % path).status == 403)
    r = run("05.folder_PATCH_rights.sh", OWNER, ["full"])
    c.check("05 full sets the rights to 7 and reads them back", r.returncode == 0 and "Read back: 7" in r.stdout, (r.stdout + r.stderr)[-300:])
    c.check("rights full: the delete that was refused works now", guest._request("DELETE", "files/%s/g3.txt" % path).status == 204)
    c.check("rights full: an upload works", guest.upload_to(SHARED_NAME, "g7.txt", b"x\n").status == 201)
    c.check("rights full: and so does deleting it", guest._request("DELETE", "files/%s/g7.txt" % path).status == 204)
    r = run("05.folder_PATCH_rights.sh", OWNER, ["1"])
    c.check("05 1 takes it back to read only", r.returncode == 0 and "Read back: 1" in r.stdout, (r.stdout + r.stderr)[-300:])
    c.check("rights read again: an upload is refused (403)", guest.upload_to(SHARED_NAME, "g1b.txt", b"x\n").status == 403)
    owner = client(OWNER)
    owner.login()

    r = run("06.folder_PATCH_unshare.sh", OWNER)
    c.check("06 exits 0", r.returncode == 0, (r.stdout + r.stderr)[-300:])
    gone = root_names(guest)
    c.check("after 06 the folder is gone from the collaborator's list", gone is not None and SHARED_NAME not in gone, gone)
    c.check("and still there for the owner", FOLDER in (root_names(owner) or []))
    guest.logout()
    owner.logout()

    # -- nothing left -----------------------------------------------------------------------------------------
    for script in ("07.folder_DELETE.sh", "99.cleanup_DELETE.sh"):
        r = run(script, OWNER)
        c.check("%s exits 0" % script, r.returncode == 0, (r.stdout + r.stderr)[-300:])
    r = run("99.cleanup_DELETE.sh", OWNER)
    c.check("99 a second time, with nothing to remove, exits 0", r.returncode == 0)
    for name in (OWNER, GUEST):
        user = client(name)
        user.login()
        left = [n for n in (root_names(user) or []) if n.startswith(FOLDER)]
        user.logout()
        c.check("%s: nothing named %s* is left" % (name, FOLDER), left == [], left)
finally:
    if OWNER in created:
        try:
            run("99.cleanup_DELETE.sh", OWNER)  # unshares and removes what the use case made, even after a failure
        except Exception as e:
            c.info("the cleanup of the owner's folder did not run: %s" % e)
    clear_local()
    for name in created:
        admin.delete("accounts/" + name)
        c.check('the throwaway account "%s" was removed' % name, not admin.exists("accounts/" + name))
    admin.logout()

sys.exit(c.done())
