#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Generates a real, brand new private certificate for a
throwaway account, runs the actual, unmodified stGetPrivateCert.py against
it, verifies a real private key was exported, and cleans up everything -
the certificate, the throwaway account, and the files the script wrote.

This is the one python3 example this project spent the longest unable to
test at all. The blocker on record - see .claude/skills/st-api-gotchas/SKILL.md,
"Importing a private certificate needs the server's own CA password" - was
about *importing* an externally created key via a multipart upload, which
needs this server's real CA password to succeed, and there was no way to
manufacture a valid one without already knowing it.

Confirmed directly, once given that real password: *generating* a brand new
certificate through a plain JSON `POST /certificates` (no multipart, no
external key file at all - `type`, `usage: "private"`, `subject`, `keySize`,
`validityPeriod`, `account`, and `caPassword`) is a completely different
code path from importing one, and accepts the very same CA password. This
check uses exactly that to create the one thing this project never had
before: a real private certificate, owned by a throwaway account, that
`stGetPrivateCert.py` can actually export.

Separately confirmed: the password of the export is not validated against
anything - it is the passphrase the *exported* file gets encrypted with, freely
chosen by the caller, not a secret you need to already know. Only the CA
password above gates anything. stGetPrivateCert.py used to send it in the URL
(GET with exportPrivateKey=true&password=...); it now asks the export
operation (POST /certificates/{id}/operations?operation=export&format=pkcs12)
and sends it as a form field, read from ST_EXPORT_PASSWORD, which this check sets.
The file it writes must be readable by its owner only, and must open with that
password and hold the private key (checked with openssl, when it is on this machine).

Needs --write, st_allow_writes="yes", AND a real st_ca_password set in
integration.conf - this check skips itself, rather than fail, when that is
blank. See integration.conf.example for what it is and why this project
cannot ship a working default for it.
"""
import email
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402


def json_body(response):
    """
    POST /certificates answers multipart/mixed even when no private key
    export was requested - confirmed directly, an Accept: application/json
    header (st_client's default on every call) does not change that.
    st_client.py stays stdlib only, so this pulls the one application/json
    part out by hand with the stdlib email parser, rather than pull in
    requests_toolbelt just for this.
    """
    content_type = response.headers.get("Content-Type") or response.headers.get("content-type", "")
    if "multipart" not in content_type:
        return response.json()
    message = email.message_from_bytes(
        ("Content-Type: %s\r\n\r\n" % content_type).encode() + response.body)
    for part in message.walk():
        if part.get_content_type() == "application/json":
            return json.loads(part.get_payload(decode=True).decode("utf-8"))
    return None

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run stGetPrivateCert.py for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

ca_password = config.get("st_ca_password", "")
if not ca_password:
    st_client.skip("st_ca_password is not set in integration.conf - see "
                   "integration.conf.example for what it is and why this "
                   "check cannot proceed without it")

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

c = st_client.Checker("stGetPrivateCert.py, run for real from Admin/API 2.0/python/python3")

PY_TREE = runner.path("Admin", "API 2.0", "python")
PY_DIR = os.path.join(PY_TREE, "python3")
SCRIPT = os.path.join(PY_DIR, "stGetPrivateCert.py")
ACCOUNT = config.get("st_object_prefix", "ZZTEST_") + "certaccount"
CERT_NAME = config.get("st_object_prefix", "ZZTEST_") + "privcert"
PKEY_FILE = os.path.join(PY_DIR, "exportedPrivateKey.p12")
EXPORT_PASSWORD = "ZzTest_export_pw_1"
LOG_FILE = os.path.join(PY_DIR, "my.log")

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /certificates certificate "
           "generation or export; run this against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

if client.exists("accounts/" + ACCOUNT):
    c.info('an account named "%s" already exists on this server; skipping '
           "this check rather than reuse it." % ACCOUNT)
    client.logout()
    sys.exit(c.done())

created_account = False
cert_id = None

try:
    response = client.post("accounts", {
        "name": ACCOUNT, "type": "user", "uid": "1998", "gid": "1998",
        "homeFolder": "/home/" + ACCOUNT,
        "user": {"name": ACCOUNT, "passwordCredentials": {"password": "Ax_ZzTest_Cert1!"}},
    })
    created_account = response.status == 201
    c.check('created a throwaway account "%s" to own the certificate' % ACCOUNT,
            created_account, response.text[:200])
    if not created_account:
        raise SystemExit(c.done())

    response = client.post("certificates", {
        "name": CERT_NAME, "subject": "CN=%s,O=Axway,C=BG" % CERT_NAME,
        "type": "x509", "usage": "private", "validityPeriod": 30, "keySize": 2048,
        "account": ACCOUNT, "caPassword": ca_password,
    })
    created_cert = response.status == 201
    c.check("generated a real, brand new private certificate", created_cert,
            response.text[:300])
    if not created_cert:
        raise SystemExit(c.done())

    cert = json_body(response) or {}
    cert_id = cert.get("id")
    c.check("the response named the new certificate's id", bool(cert_id), cert)
    c.check("it is chained to a trusted root, not self-signed adrift",
            "trusted" in str(cert.get("validationStatus", "")).lower(),
            cert.get("validationStatus"))

    os.environ["ST_EXPORT_PASSWORD"] = EXPORT_PASSWORD
    try:
        with runner.real_credentials_python(PY_TREE, config):
            result = runner.run_python(SCRIPT, [cert_id])
    finally:
        del os.environ["ST_EXPORT_PASSWORD"]
    c.check("stGetPrivateCert.py runs without a shell level error",
            result.returncode == 0,
            (result.stdout + result.stderr).strip()[-300:] if result.returncode else "")
    c.check("its own output confirms the export",
            "Private Key exported with filename" in result.stdout, result.stdout[-300:])
    c.check("the password is not in its output", EXPORT_PASSWORD not in result.stdout + result.stderr)

    c.check("the exported private key file was written", os.path.exists(PKEY_FILE))
    if os.path.exists(PKEY_FILE):
        c.check("and is readable by its owner only (0600)",
                (os.stat(PKEY_FILE).st_mode & 0o777) == 0o600, oct(os.stat(PKEY_FILE).st_mode))
        if shutil.which("openssl"):
            info = subprocess.run(["openssl", "pkcs12", "-in", PKEY_FILE, "-passin", "pass:" + EXPORT_PASSWORD,
                                   "-info", "-noout"], capture_output=True, text=True)
            c.check("openssl opens it with that password, and it holds the private key",
                    info.returncode == 0 and "Shrouded Keybag" in info.stderr, info.stderr[-300:])
    if os.path.exists(PKEY_FILE):
        with open(PKEY_FILE, "rb") as f:
            content = f.read()
        # A PKCS#12 file is DER encoded, starting with a SEQUENCE tag (0x30).
        c.check("the exported file is non-trivial and DER encoded (PKCS#12)",
                len(content) > 500 and content[0:1] == b"\x30",
                (len(content), content[:8]))

finally:
    if cert_id:
        client.delete("certificates/" + cert_id)
        c.check("the throwaway certificate was removed", not client.exists("certificates/" + cert_id))
    if created_account:
        client.delete("accounts/" + ACCOUNT)
        c.check('the throwaway account "%s" was removed' % ACCOUNT,
                not client.exists("accounts/" + ACCOUNT))
    for f in (PKEY_FILE, LOG_FILE):
        if os.path.exists(f):
            os.remove(f)
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own calls)"
       % client.calls)

sys.exit(c.done())
