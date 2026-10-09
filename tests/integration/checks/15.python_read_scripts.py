#!/usr/bin/env python3
"""
Read only. Runs the actual, unmodified python3 scripts
stGetAccountsAfterDate.py and stConfigScan.py in Admin/API 2.0/python/python3
against a configured server, and independently verifies what each claims.

Needs tests/local/pyvenv - a venv holding requests, the third-party
library these examples import. st_client.py stays stdlib
only on purpose (see its own docstring); the examples it runs were written
against requests, the same way the bash examples assume curl and jq are on
PATH. Create it once with:

    python3 -m venv tests/local/pyvenv
    tests/local/pyvenv/bin/pip install requests

No object is created on the server by either script, so this needs no
--write. stConfigScan.py writes a local baseline file, a JSON file whose path is
its second argument (it used to be a pickle at /home/axway/stConfig.baseline, a
path that only exists on a real ST host); this check gives it a file in
tests/local, so the real, unmodified script runs. It also leaves a log file,
checkConfig.log, next to itself; this check removes it afterward.

Confirmed and fixed while getting this running the first time: both scripts
crashed on this machine (and on any non-Linux POSIX system - macOS, BSD) with
AttributeError, because os.sched_getaffinity is Linux-only even though
os.name == 'posix' is also true elsewhere. See the gotchas skill.
"""
import json
import os
import stat
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see this check's own docstring to create one")

c = st_client.Checker("Python read-only scripts, run for real from Admin/API 2.0/python/python3")

PY_TREE = runner.path("Admin", "API 2.0", "python")
PY_DIR = os.path.join(PY_TREE, "python3")


def script(name):
    return os.path.join(PY_DIR, name)


client = harness.connect(config, c, mock=("the bundled mock does not implement enough of the admin API for "
                                          "these scripts; run this against a real server to exercise it"))

with runner.real_credentials_python(PY_TREE, config):

    # -- stGetAccountsAfterDate.py -------------------------------------------
    result = runner.run_python(script("stGetAccountsAfterDate.py"), ["2000-01-01"])
    c.check("stGetAccountsAfterDate.py runs without a shell level error",
            result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")

    real_users = list(client.page("accounts", params={"type": "user"}))
    c.check("its own reported count matches an independent GET /accounts?type=user",
            ("There were:  %d  created in this time period" % len(real_users)) in result.stdout,
            result.stdout[-300:])
    for account in real_users:
        c.check("%s is named in its output" % account.get("name"),
                account.get("name") in result.stdout)

    # -- stConfigScan.py, with a baseline file of its own in tests/local -----
    baseline = runner.path("tests", "local", "ZZTEST_stConfig.baseline")

    real_options = {o.get("name"): o.get("values")
                    for o in client.page("configurations/options")}

    try:
        result = runner.run_python(script("stConfigScan.py"), ["MAKEBASELINE", baseline])
        c.check("stConfigScan.py MAKEBASELINE runs without a shell level error",
                result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")
        c.check("the baseline file was written", os.path.exists(baseline))
        if os.path.exists(baseline):
            with open(baseline) as f:
                saved = json.load(f)
            c.check("it is JSON and holds every option the server lists (read independently)",
                    set(real_options) <= set(saved), sorted(set(real_options) - set(saved))[:5])
            c.check("and is readable by its owner only",
                    stat.S_IMODE(os.stat(baseline).st_mode) == 0o600, oct(os.stat(baseline).st_mode))

        result = runner.run_python(script("stConfigScan.py"), ["COMPAREBASELINE", baseline])
        c.check("stConfigScan.py COMPAREBASELINE runs without a shell level error",
                result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")
        c.check("it reports its differences, in both directions",
                "Differences: " in result.stdout, result.stdout[-500:])
        if "Differences: 0 changed, 0 new, 0 gone" not in result.stdout:
            c.info("the server's options changed between the two runs: " + result.stdout[-300:].replace("\n", " | "))
    finally:
        if os.path.exists(baseline):
            os.remove(baseline)
        logfile = os.path.join(PY_DIR, "checkConfig.log")
        if os.path.exists(logfile):
            os.remove(logfile)

client.logout()
c.info("%d API calls issued by the verification client (not counting the scripts' own calls)"
       % client.calls)

sys.exit(c.done())
