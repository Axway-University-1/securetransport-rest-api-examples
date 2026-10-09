#!/usr/bin/env python3
"""
CHANGES NOTHING ON THE SERVER, and never sends the stop. Runs the real, unmodified
34.TransactionManager examples as far as they can be run safely.

Stopping the Transaction Manager is server wide and has no way back through the API
(there is no start operation), so this check never sends it, not even a wrong one:

  01 (the status): run for real. It must exit 0 and print the status the API gives
     (the Transaction Manager is running on a healthy lab). The other methods and
     accept types the endpoint refuses are checked the same way the examples' Notes
     say: HEAD 200, PUT, PATCH and DELETE 405 on both paths, GET on /operations 405,
     xml and csv 406, an unknown sub path 404, fields= ignored.
  02 (the stop): run only down the refusal path. It is run with a FAKE curl in front
     of the real one on PATH, which records any call it gets and answers nothing, so
     even a script that wrongly went on to send could not reach the server. Each run
     must exit 2, print that nothing was sent, and leave the fake curl's log empty:
     no argument, a wrong word, the right word with a bad second or third argument.
     The right word with good arguments is NEVER run, here or anywhere else in this
     repository's checks against a server: the offline suite covers that path with
     a stub curl (tests/checks/test_bash_admin_api.sh).
  Afterwards the API still says the Transaction Manager is running, as before.

Needs no --write, nothing here writes. The bundled mock does not implement
/transactionManager, so against it the check only says so.
"""
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

c = st_client.Checker("Transaction Manager, run from Admin/API 2.0/bash/34.TransactionManager (the stop is never sent)")
BASH = runner.path("Admin", "API 2.0", "bash")
FOLDER = os.path.join(BASH, "34.TransactionManager")
STOP = "02.transactionManager_operations_POST_stop.sh"
WORD = "stop-the-transaction-manager"

admin = harness.connect(config, c, mock="the bundled mock does not implement /transactionManager")


def refusal(args):
    """Run the stop script with a fake curl first on PATH. Returns (rc, output, calls the fake saw)."""
    with tempfile.TemporaryDirectory() as tmp:
        log = os.path.join(tmp, "calls.log")
        fake = os.path.join(tmp, "curl")
        with open(fake, "w") as f:
            f.write('#!/bin/bash\necho "$@" >> "%s"\nexit 99\n' % log)
        os.chmod(fake, 0o755)
        env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"])
        result = subprocess.run(["bash", STOP] + args, cwd=FOLDER, capture_output=True, text=True, timeout=60, env=env)
        calls = open(log).read() if os.path.exists(log) else ""
    return result.returncode, result.stdout + result.stderr, calls


try:
    before = admin.get("transactionManager")
    c.check("GET /transactionManager is 200 with a status", before.status == 200 and "status" in before.json(), before.text[:200])
    status = before.json().get("status", "")
    c.info("the status the server gives: %r" % status)
    c.check("the Transaction Manager is running (this check will not go on otherwise)", "Running" in status, status)

    for method, path, want in (("head", "transactionManager", 200),
                               ("put", "transactionManager", 405), ("patch", "transactionManager", 405),
                               ("delete", "transactionManager", 405),
                               ("get", "transactionManager/operations", 405), ("put", "transactionManager/operations", 405),
                               ("delete", "transactionManager/operations", 405), ("get", "transactionManager/x", 404)):
        func = getattr(admin, method)
        r = func(path) if method in ("head", "get", "delete") else func(path, {})
        c.check("%s /%s is %s" % (method.upper(), path, want), r.status == want, "%s %s" % (r.status, r.text[:100]))
    for accept in ("application/xml", "text/csv"):
        r = admin._request("GET", "transactionManager", extra_headers={"Accept": accept})
        c.check("GET with Accept %s is 406" % accept, r.status == 406, "%s %s" % (r.status, r.text[:100]))
    r = admin.get("transactionManager", params={"fields": "nope"})
    c.check("fields= is ignored, even an unknown one", r.status == 200 and r.json() == before.json(), r.text[:100])

    with runner.real_credentials(BASH, config):
        # --- 01, for real
        result = runner.run(os.path.join(FOLDER, "01.transactionManager_GET.sh"), timeout=60)
        out = result.stdout + result.stderr
        c.check("01 exits 0 while the Transaction Manager runs", result.returncode == 0, out[-300:])
        c.check("01 prints the status the API gives", "Transaction Manager status: %s" % status in out, out[-300:])

        # --- 02, the refusal path only, behind a fake curl
        refusals = [[], [""], ["yes"], ["STOP"], ["stop"], [WORD + "x"], ["x" + WORD], ["true"],
                    [WORD, "maybe"], [WORD, "false", "30"], [WORD, "true", "3x"], [WORD, "true", "-5"],
                    [WORD, "true", "10", "more"]]
        for args in refusals:
            rc, out, calls = refusal(args)
            c.check("02 with %s exits 2 and sends nothing" % (args or "no argument"), rc == 2 and calls == "", "rc %s, calls %r, %s" % (rc, calls, out[-200:]))
        rc, out, calls = refusal([])
        c.check("02 with no argument says that nothing was sent", "Nothing was sent." in out, out[-300:])
        # the fake curl proves itself: a run that goes on would be recorded. Run the script's GET sibling with it
        with tempfile.TemporaryDirectory() as tmp:
            log = os.path.join(tmp, "calls.log")
            fake = os.path.join(tmp, "curl")
            with open(fake, "w") as f:
                f.write('#!/bin/bash\necho "$@" >> "%s"\nexit 99\n' % log)
            os.chmod(fake, 0o755)
            env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"])
            subprocess.run(["bash", "01.transactionManager_GET.sh"], cwd=FOLDER, capture_output=True, text=True, timeout=60, env=env)
            c.check("the fake curl does record a call, so an empty log above means nothing was sent",
                    os.path.exists(log) and "transactionManager" in open(log).read())

    after = admin.get("transactionManager")
    c.check("afterwards the Transaction Manager is still as before: %s" % after.json().get("status"),
            after.status == 200 and after.json() == before.json(), after.text[:200])
finally:
    admin.logout()

sys.exit(c.done())
