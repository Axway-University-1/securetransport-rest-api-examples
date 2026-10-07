#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 11.Certificates examples:
generates example_cert with the server's CA, lists, checks, reads and patches
it, exports it as pem, crt and pkcs12, imports the pem as a partner
certificate for a throwaway account, then a certificate signing request:
generated, listed, read, signed by a throwaway CA made here with openssl,
completed, and a second one deleted. Each effect is checked through the API.

Needs --write, st_allow_writes="yes", and the server CA's password in
st_ca_password. The CSR is signed only when openssl is installed.

Refuses to start when any of the example objects exist; removes all of them,
and the files the examples write into their folder, in a finally block.
"""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the certificate examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')
if not config.get("st_ca_password"):
    st_client.skip("st_ca_password is not set in integration.conf: generating a certificate needs it")

c = st_client.Checker("Certificates, run for real from Admin/API 2.0/bash/11.Certificates")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "11.Certificates")
ACCOUNT = "example_cert_user"
NAMES = ("example_cert", "example_partner", "example_csr_cert")
SUBJECT = "CN=example_csr,O=Example"
WRITTEN = ("example_cert.pem", "example_cert.crt", "example_cert.p12", "example_csr.req")


def script(name, args=None, expect_rc=0):
    result = runner.run(os.path.join(FOLDER, name), args, timeout=90)
    out = result.stdout + result.stderr
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc,
            out.strip()[-300:])
    return out


def certs(name):
    return (admin.get("certificates", params={"name": name, "fields": "id,name,usage,account,accessLevel,"
                                                              "additionalAttributes,validationStatus"}).json()
            or {}).get("result", [])


def requests():
    return (admin.get("certificates/requests", params={"subject": SUBJECT}).json() or {}).get("result", [])


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /certificates")
    admin.logout()
    sys.exit(c.done())
if any(certs(n) for n in NAMES) or requests() or admin.exists("accounts/" + ACCOUNT):
    c.check("the example certificates, requests and %s do not exist yet" % ACCOUNT, False,
            "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

work = tempfile.mkdtemp(prefix="st_certs_")
os.environ["CA_PASSWORD"] = config["st_ca_password"]
os.environ["EXPORT_PASSWORD"] = "Example-Export-1"
try:
    c.check("set up: the account", admin.post("accounts", {
        "name": ACCOUNT, "type": "user", "homeFolder": "/home/" + ACCOUNT, "uid": "10002", "gid": "10002",
        "user": {"name": ACCOUNT, "passwordCredentials": {"password": "Ex-a1b2c3d4!aA1"}}}).status == 201)
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        out = script("02.certificates_POST_generate.sh", ["30"])
        made = certs("example_cert")
        c.check("02 generated one local example_cert", [x.get("usage") for x in made] == ["local"], made)
        c.check("02 printed its id, from Location", bool(made) and made[0]["id"] in out, out[-200:])

        out = script("01.certificates_GET.sh", ["local", "40"])
        c.check("01 lists it among the ones that expire within 40 days (milliseconds)",
                out.split("expire within 40 days:")[-1].count("  example_cert  ") == 1, out[-300:])
        out = script("01.certificates_GET.sh", ["local", "20"])
        c.check("01 and not within 20", "  example_cert  " not in out.split("expire within 20 days:")[-1], out[-300:])
        out = script("04.certificates_id_HEAD.sh")
        c.check("04 finds it", "The certificate example_cert exists" in out, out[-200:])
        out = script("05.certificates_id_GET.sh")
        c.check("05 prints its SHA256 fingerprint and its path to the CA",
                "Its SHA256 fingerprint: SHA256:" in out and out.count("\n  ") >= 2, out[-300:])
        script("06.certificates_id_PATCH.sh")
        now = certs("example_cert")[0]
        c.check("06 PATCH made it PUBLIC and tagged it",
                (now.get("accessLevel"), now.get("additionalAttributes")) == ("PUBLIC", {"userVars.owner": "example"}), now)

        for fmt, ext, check in (("pem", "pem", lambda b: b.startswith(b"-----BEGIN CERTIFICATE-----")),
                                ("crt", "crt", lambda b: b[:1] == b"\x30"),
                                ("pkcs12", "p12", lambda b: b[:1] == b"\x30" and len(b) > 1500)):
            script("08.certificates_id_operations_POST_export.sh", ["example_cert", fmt])
            path = os.path.join(FOLDER, "example_cert." + ext)
            data = open(path, "rb").read() if os.path.exists(path) else b""
            c.check("08 exported %s to example_cert.%s" % (fmt, ext), check(data), len(data))
        shutil.copy(os.path.join(FOLDER, "example_cert.pem"), work)

        out = script("03.certificates_POST_import_partner.sh", [ACCOUNT, os.path.join(work, "example_cert.pem")])
        partner = certs("example_partner")
        c.check("03 imported it as the account's partner certificate",
                [(x.get("usage"), x.get("account")) for x in partner] == [("partner", ACCOUNT)], partner)

        # --- a certificate signing request
        out = script("09.certificates_requests_POST.sh")
        pending = requests()
        c.check("09 created one request", len(pending) == 1, pending)
        req = os.path.join(FOLDER, "example_csr.req")
        c.check("09 wrote the CSR", os.path.exists(req) and open(req).read().startswith("-----BEGIN CERTIFICATE REQUEST-----"))
        out = script("10.certificates_requests_GET.sh", ["local"])
        c.check("10 lists it", pending and ("  %s  %s" % (pending[0]["id"], SUBJECT)) in out, out[-300:])
        out = script("11.certificates_requests_id_HEAD.sh")
        c.check("11 finds it by its subject", "exists" in out, out[-200:])
        out = script("12.certificates_requests_id_GET.sh")
        c.check("12 reads it", SUBJECT in out, out[-200:])

        if shutil.which("openssl") and os.path.exists(req):
            ca_key, ca_pem, signed = (os.path.join(work, n) for n in ("ca.key", "ca.pem", "signed.pem"))
            subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", ca_key, "-out", ca_pem,
                            "-days", "2", "-subj", "/CN=example_ca"], capture_output=True, check=True)
            subprocess.run(["openssl", "x509", "-req", "-in", req, "-CA", ca_pem, "-CAkey", ca_key, "-CAcreateserial",
                            "-CAserial", os.path.join(work, "ca.srl"), "-out", signed, "-days", "2"],
                           capture_output=True, check=True)
            script("13.certificates_requests_id_POST_complete.sh", [signed])
            done = certs("example_csr_cert")
            c.check("13 completed it into the local certificate example_csr_cert",
                    [x.get("usage") for x in done] == ["local"], done)
            c.check("13 the request is gone", requests() == [])
            script("07.certificates_id_DELETE.sh", ["example_csr_cert"])
            c.check("07 deleted example_csr_cert", certs("example_csr_cert") == [])
        else:
            c.info("openssl is not installed, so the request was not signed and completed")
            script("14.certificates_requests_id_DELETE.sh")

        script("09.certificates_requests_POST.sh")
        script("14.certificates_requests_id_DELETE.sh")
        c.check("14 deleted the second request", requests() == [])

        script("07.certificates_id_DELETE.sh")
        c.check("07 deleted example_cert", certs("example_cert") == [])
        admin.delete("accounts/" + ACCOUNT)
        c.check("deleting the account deleted its partner certificate", certs("example_partner") == [])
finally:
    if admin.exists("accounts/" + ACCOUNT):
        admin.delete("accounts/" + ACCOUNT)
    for name in NAMES:
        for x in certs(name):
            admin.delete("certificates/" + x["id"])
    for x in requests():
        admin.delete("certificates/requests/" + x["id"])
    for name in WRITTEN:
        if os.path.exists(os.path.join(FOLDER, name)):
            os.remove(os.path.join(FOLDER, name))
    shutil.rmtree(work, ignore_errors=True)
    c.check("nothing is left behind", not any(certs(n) for n in NAMES) and requests() == []
            and not admin.exists("accounts/" + ACCOUNT)
            and not any(os.path.exists(os.path.join(FOLDER, n)) for n in WRITTEN))
    admin.logout()

sys.exit(c.done())
