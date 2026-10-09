#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual stBuildFullTestAccount.py end to end:
account, an imported SSH private key, a folder-monitor site, an SFTP site
authenticating with that key, a subscription and two routes (simple and
composite) - verifies all seven objects, then deletes every one of them.

This was the python3 example with the most unmet preconditions in the
project: a route TEMPLATE named exactly `Empty`, an application named
exactly `AdvRouting`, a local key file named `testsshkey`, and this
server's own CA password (needed for the certificate import, not just
generation - see 26.python_get_private_cert.py and
.claude/skills/st-api-gotchas/SKILL.md). All four are met here: this check
creates disposable `ZZTEST_`-prefixed stand-ins for the template and
application and substitutes the script's own hardcoded references to
point at them, generates a real, disposable SSH keypair with `ssh-keygen`
for the key file, and reads the real CA password from
`st_ca_password` in integration.conf (skipping itself if that is blank).

Two real, confirmed bugs were found and fixed in the shipped script while
getting this to run for the first time, both in `stImportKey`/`stGetKeyId`:
they hardcoded the literal account name `"TestAccount1"` instead of using
the script's own configured `accName` variable, which every other function
in the file already does correctly. Confirmed directly: importing a
certificate against a nonexistent account name gets a 403, not the 404 you
might expect - this had nothing to do with CSRF or permissions, the account
this ran against simply never existed under that hardcoded name once
`accName` was set to anything else.

Also confirmed directly, while chasing that 403 down: a GET call inside a
kept session does not need a `csrfToken` the way a POST/PATCH/PUT/DELETE
does - `stGetKeyId()` and `stGetTemplateRouteId()` never send one, and
that turned out to be fine. CSRF here gates writes, not reads.

Needs --write, st_allow_writes="yes", AND a real st_ca_password set in
integration.conf, same as 26.python_get_private_cert.py. Also needs
ssh-keygen on PATH (standard on macOS and Linux).
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run stBuildFullTestAccount.py for real")

ca_password = config.get("st_ca_password", "")
if not ca_password:
    st_client.skip("st_ca_password is not set in integration.conf - see "
                   "integration.conf.example for what it is and why this "
                   "check cannot proceed without it")

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

if subprocess.run(["which", "ssh-keygen"], capture_output=True).returncode != 0:
    st_client.skip("no ssh-keygen on PATH - needed to generate a disposable test key")

c = st_client.Checker("stBuildFullTestAccount.py, run for real from "
                       "Admin/API 2.0/python/python3")

PY_TREE = runner.path("Admin", "API 2.0", "python")
PY_DIR = os.path.join(PY_TREE, "python3")
SCRIPT = os.path.join(PY_DIR, "stBuildFullTestAccount.py")

ACC_NAME = "ZZTEST_stBuildFullTestAccount"
TEMPLATE_NAME = "ZZTEST_emptytemplate"
APP_NAME = "ZZTEST_advrouting"
KEY_FILE = os.path.join(PY_DIR, "testsshkey")
KEY_PASSPHRASE = "change_me"  # matches the script's own "password" field for the key

client = harness.connect(config, c, mock=("the bundled mock does not implement /certificates, /sites, "
           "/subscriptions import/creation; run this against a real server "
           "to exercise it"))

if client.exists("accounts/" + ACC_NAME):
    c.info('an account named "%s" already exists on this server; skipping '
           "this check rather than reuse it." % ACC_NAME)
    client.logout()
    sys.exit(c.done())

created_account = False
created_template_id = None
created_app = False
key_written = False

try:
    response = client.post("routes", {"name": TEMPLATE_NAME, "type": "TEMPLATE",
                                      "conditionType": "MATCH_ALL"})
    c.check('created a throwaway route template "%s" (stand-in for "Empty")' % TEMPLATE_NAME,
            response.status == 201, response.text[:200])
    created_template_id = response.headers.get("Location", "").rstrip("/").rsplit("/", 1)[-1]

    response = client.post("applications", {"type": "AdvancedRouting", "name": APP_NAME})
    created_app = response.status == 201
    c.check('created a throwaway AdvancedRouting application "%s" (stand-in for "AdvRouting")'
            % APP_NAME, created_app, response.text[:200])

    subprocess.run(["ssh-keygen", "-t", "rsa", "-b", "2048", "-f", KEY_FILE,
                    "-N", KEY_PASSPHRASE, "-q", "-C", "zztest"], check=True)
    key_written = os.path.exists(KEY_FILE)
    c.check("generated a disposable local SSH keypair for the import", key_written)

    with runner.real_credentials_python(PY_TREE, config):
        subs = {
            "accName = 'TestAccount1'": "accName = '%s'" % ACC_NAME,
            "homeFolder = '/usrdata/NoBU/' + accName": "homeFolder = '/home/' + accName",
            "templateRouteName = 'Empty'": "templateRouteName = '%s'" % TEMPLATE_NAME,
            '"caPassword": "change_me"': '"caPassword": "%s"' % ca_password,
            '"application": "AdvRouting"': '"application": "%s"' % APP_NAME,
            '"host": "<SERVER>"': '"host": "%s"' % config["st_server"],
        }
        with runner.substituted_copy(SCRIPT, subs) as copy:
            result = runner.run_python(copy, timeout=90)
            c.check("stBuildFullTestAccount.py runs without a shell level error",
                    result.returncode == 0,
                    result.stderr.strip()[-500:] if result.returncode else "")
            c.check('its own output confirms the composite route ("Package Route Id") was created',
                    "Package Route Id:" in result.stdout, result.stdout[-300:])

    created_account = client.exists("accounts/" + ACC_NAME)
    c.check("the account was really created", created_account)

    certs = list(client.page("certificates", params={"account": ACC_NAME}))
    c.check("a private ssh certificate was imported for the account",
            any(cc.get("type") == "ssh" and cc.get("usage") == "private" for cc in certs), certs)

    sites = {s.get("name") for s in client.page("sites", params={"account": ACC_NAME})}
    c.check("both sites (FolderMonitor, SFTPsite) were created",
            {"FolderMonitor", "SFTPsite"} <= sites, sites)

    subs_created = list(client.page("subscriptions", params={"account": ACC_NAME}))
    c.check("the AdvancedRouting subscription was created",
            any(s.get("type") == "AdvancedRouting" and s.get("application") == APP_NAME
                for s in subs_created), subs_created)

    c.check("the simple route was created",
            client.get("routes", params={"name": "SimpleRouteToSFTPsite"}).json()
            .get("resultSet", {}).get("returnCount") == 1)
    c.check("the composite/package route was created",
            client.get("routes", params={"name": "PackageRouteToSFTPsite"}).json()
            .get("resultSet", {}).get("returnCount") == 1)

finally:
    for name in ("PackageRouteToSFTPsite", "SimpleRouteToSFTPsite"):
        matches = list(client.page("routes", params={"name": name, "fields": "id"}))
        for r in matches:
            client.delete("routes/" + r["id"])
    for name in ("FolderMonitor", "SFTPsite"):
        matches = list(client.page("sites", params={"name": name, "fields": "id"}))
        for s in matches:
            client.delete("sites/" + s["id"])
    if created_account:
        client.delete("accounts/" + ACC_NAME)  # cascades the imported certificate
        c.check('the throwaway account "%s" was removed' % ACC_NAME,
                not client.exists("accounts/" + ACC_NAME))
    if created_template_id:
        client.delete("routes/" + created_template_id)
        c.check('the throwaway route template "%s" was removed' % TEMPLATE_NAME,
                not client.exists("routes/" + created_template_id))
    if created_app:
        client.delete("applications/" + APP_NAME)
        c.check('the throwaway application "%s" was removed' % APP_NAME,
                not client.exists("applications/" + APP_NAME))
    if key_written:
        for f in (KEY_FILE, KEY_FILE + ".pub"):
            if os.path.exists(f):
                os.remove(f)
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own calls)"
       % client.calls)

sys.exit(c.done())
