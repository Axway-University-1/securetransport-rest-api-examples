#!/usr/bin/env python3
"""
Read only. Runs the actual, unmodified python3 scripts
stUsersPerSharedFolder.py and stCertificateExpiry.py in
Admin/API 2.0/python/python3 against a configured server, and independently
verifies what each claims.

Both scripts only ever GET and print - no object is created, changed or
deleted anywhere - so this needs no --write, the same way
15.python_read_scripts.py does not.

Needs tests/local/pyvenv - see 15.python_read_scripts.py's own docstring for
how to create one.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

c = st_client.Checker("Python read-only report scripts, run for real from "
                       "Admin/API 2.0/python/python3")

PY_TREE = runner.path("Admin", "API 2.0", "python")
PY_DIR = os.path.join(PY_TREE, "python3")


def script(name):
    return os.path.join(PY_DIR, name)


client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement enough of the admin API for "
           "these scripts; run this against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

with runner.real_credentials_python(PY_TREE, config):

    # -- stUsersPerSharedFolder.py --------------------------------------------
    result = runner.run_python(script("stUsersPerSharedFolder.py"))
    c.check("stUsersPerSharedFolder.py runs without a shell level error",
            result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")

    real_shared_folder_apps = [a for a in client.page("applications")
                               if a.get("type") == "SharedFolder"]
    c.check("its own reported application count matches an independent GET /applications",
            ("Found " + str(len(real_shared_folder_apps)) + " SharedFolder applications")
            in result.stdout, result.stdout[-300:])
    for app in real_shared_folder_apps:
        c.check("%s is named in its output" % app.get("name"),
                str(app.get("name")) in result.stdout)
    c.check("it reports completion", "Completed Run" in result.stdout, result.stdout[-200:])

    # -- stCertificateExpiry.py -----------------------------------------------
    result = runner.run_python(script("stCertificateExpiry.py"))
    c.check("stCertificateExpiry.py runs without a shell level error",
            result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")

    real_certificates = list(client.page("certificates"))
    c.check("its own reported total matches an independent GET /certificates",
            ("Total certificates: " + str(len(real_certificates))) in result.stdout,
            result.stdout[-300:])

    real_by_usage = {}
    for cert in real_certificates:
        usage = str(cert.get("usage", "unknown"))
        real_by_usage[usage] = real_by_usage.get(usage, 0) + 1
    for usage, count in real_by_usage.items():
        c.check("usage %r count (%d) is reported" % (usage, count),
                ("   " + usage + ": " + str(count)) in result.stdout, result.stdout[-500:])
    c.check("it reports completion", "Completed Run" in result.stdout, result.stdout[-200:])

client.logout()
c.info("%d API calls issued by the verification client (not counting the scripts' own calls)"
       % client.calls)

sys.exit(c.done())
