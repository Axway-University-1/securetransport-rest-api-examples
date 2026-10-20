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


def run(script, user, **env):
    cfg = dict(config, st_port=ENDUSER_PORT, st_user=user, st_password=PASSWORDS[user])
    with runner.real_credentials(ENDUSER_TREE, cfg):
        return runner.run(os.path.join(UC, script), env=env, timeout=300)
COOKIE_JAR = os.path.join(ENDUSER_TREE, "myCookie.jar")


def clear_local():
    for leftover in ("session.cookie.jar", "state.local.csrf"):
        p = os.path.join(UC, leftover)
        if os.path.exists(p):
            os.remove(p)


def client(name):
    return st_client.EndUserClient(config["st_server"], ENDUSER_PORT, name, PASSWORDS[name])


def put_file(user, folder, filename, content):
    boundary = "----STSharingBoundary"
    body = (("--%s\r\n" % boundary).encode()
            + ('Content-Disposition: form-data; name="file"; filename="%s"\r\n\r\n' % filename).encode()
            + content + ("\r\n--%s--\r\n" % boundary).encode())
    return user._request("POST", "files/" + urllib.parse.quote(folder), headers={"Content-Type": "multipart/form-data; boundary=" + boundary}, data=body)


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
    run("99.cleanup_DELETE.sh", NOMAIL)

    # -- the whole use case ------------------------------------------------------------------------------
    r = run("00.run_all.sh", OWNER, ST_SHARE_WITH=EMAIL[GUEST])
    c.check("00.run_all.sh as the owner, sharing with the collaborator, exits 0", r.returncode == 0, (r.stdout + r.stderr)[-400:])
    c.check("it ended with the cleanup", "Cleaned up." in r.stdout, r.stdout[-200:])
    clear_local()

    # -- step by step, with the collaborator's own view ------------------------------------------------------
    for script in ("01.sharing_GET_myself.sh", "02.folder_POST.sh", "03.folder_PATCH_share.sh"):
        r = run(script, OWNER, ST_SHARE_WITH=EMAIL[GUEST])
        c.check("%s exits 0" % script, r.returncode == 0, (r.stdout + r.stderr)[-300:])
    guest = client(GUEST)
    guest.login()
    names = root_names(guest)
    c.check('the collaborator sees "%s" in their root' % SHARED_NAME, names is not None and SHARED_NAME in names, names)
    path = urllib.parse.quote(SHARED_NAME)
    c.check("and can read the file in it", guest._request("GET", "files/%s/notes.txt" % path).status == 200)
    c.check("rights 1: an upload is refused (403)", put_file(guest, SHARED_NAME, "g1.txt", b"x\n").status == 403)
    c.check("rights 1: a delete is refused (403)", guest._request("DELETE", "files/%s/notes.txt" % path).status == 403)
    r = run("04.folder_GET_sharing.sh", OWNER)
    c.check("04 shows the collaborator and the rights", EMAIL[GUEST] in r.stdout and "rights:        1 (read)" in r.stdout, r.stdout[-300:])

    r = run("05.folder_PATCH_rights.sh", OWNER)
    c.check("05 sets 3 and 7, reading each back", r.returncode == 0, (r.stdout + r.stderr)[-300:])
    # 05 ends on 7: with 7 an upload and a delete both work; go back to 3 by hand to see its in-between behaviour
    c.check("rights 7: an upload works", put_file(guest, SHARED_NAME, "g7.txt", b"x\n").status == 201)
    c.check("rights 7: and so does deleting it", guest._request("DELETE", "files/%s/g7.txt" % path).status == 204)
    owner = client(OWNER)
    owner.login()
    patch3 = owner._request("PATCH", "files/" + FOLDER, {"Content-Type": "application/json"},
                            b'[{"op":"replace","path":"/sharedDirectoryProperties/shareRights","value":3}]')
    c.check("the owner sets the rights to 3 again (204)", patch3.status == 204, patch3.status)
    c.check("rights 3: an upload works", put_file(guest, SHARED_NAME, "g3.txt", b"x\n").status == 201)
    c.check("rights 3: a delete of their file is refused (403)", guest._request("DELETE", "files/%s/g3.txt" % path).status == 403)
    owner._request("PATCH", "files/" + FOLDER, {"Content-Type": "application/json"},
                   b'[{"op":"replace","path":"/sharedDirectoryProperties/shareRights","value":7}]')
    guest._request("DELETE", "files/%s/g3.txt" % path)

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
