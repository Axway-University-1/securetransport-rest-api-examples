#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the two features end to end, 00.run_all.sh --cleanup, each in a scratch copy of its folder
with settings of its own, so nothing of an earlier run by hand (settings.local.sh, state.local.sh, the sites, routes
and partner accounts it made) is touched or reused:

  - Features/audit-billable-transfers: three accounts (a test account and two partners), pulls, routes and pushes,
    the billable report; then the cleanup.
  - Features/trigger-route-after-completed-pull: the account, a pull site and a push site, the routes, the trigger
    file; then the cleanup.

Every object has a ZZTEST_ name (account, partners, sites, application, routes), and the check proves that no
account is left. Needs the server's SSH listener (the partners are reached through it) and the End User port. The
run takes a few minutes: the features pause between steps for the pulls to run.

Needs --write and st_allow_writes="yes".
"""
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the two features for real and clean up")

c = st_client.Checker("Features run end to end (00.run_all.sh --cleanup), with names of their own")

admin = harness.connect(config, c, mock="the bundled mock has no SSH listener to pull from; run this against a real server")
ports = harness.ports(config, admin)
SSH_HOST = config.get("st_ssh_host") or config["st_server"]
TAG = "ZZTEST_ft" + harness.suffix(4)
PASSWORD = harness.new_password()
FEATURES = runner.path("Features")
BASH_TREE = runner.path("Admin", "API 2.0", "bash")


def scratch_copy(feature, settings):
    root = harness.scratch("st_feature_")
    shutil.copytree(os.path.join(FEATURES, "lib"), os.path.join(root, "Features", "lib"))
    dest = os.path.join(root, "Features", feature)
    shutil.copytree(os.path.join(FEATURES, feature), dest,
                    ignore=shutil.ignore_patterns("settings.local.*", "state.local.*"))
    with open(os.path.join(dest, "settings.local.sh"), "w") as f:
        f.write("#!/bin/bash\n" + "".join("export %s='%s'\n" % kv for kv in settings))
    return dest


def download(folder, account):
    # not numbered, so run_all does not run it: a file the run left in the test account, read three times
    r = runner.run(os.path.join(folder, "files_GET_download.sh"), ["subscription/s1/only_inbound.txt", "3", account], timeout=120)
    c.check("audit-billable-transfers: files_GET_download.sh reads a delivered file three times and exits 0",
            r.returncode == 0, (r.stdout + r.stderr)[-400:])


def run_feature(title, feature, settings, args, accounts, between=None):
    """00.run_all.sh with `args`; `between(folder)` runs while everything it made is still there (then the cleanup)."""
    folder = scratch_copy(feature, settings)
    with runner.real_credentials(BASH_TREE, config):
        r = runner.run(os.path.join(folder, "00.run_all.sh"), args, timeout=900)
        if between:
            between(folder)
            gone = runner.run(os.path.join(folder, "99.cleanup_DELETE.sh"), [args[0]], timeout=300)
            c.check("%s: 99.cleanup_DELETE.sh exits 0" % title, gone.returncode == 0, (gone.stdout + gone.stderr)[-400:])
    out = r.stdout + r.stderr
    c.check("%s: 00.run_all.sh exits 0" % title, r.returncode == 0, "exit %s\n%s" % (r.returncode, out[-600:]))
    c.check("%s: no step answered 4xx or 5xx" % title, not re.search(r"^HTTP [45]\d\d", out, re.M), out[-400:])
    left = [n for n in accounts if admin.exists("accounts/" + n)]
    c.check("%s: the cleanup left no account behind" % title, not left, left)
    for name in left:
        admin.delete("accounts/" + name)


try:
    bt = TAG + "_bt"
    run_feature("audit-billable-transfers", "audit-billable-transfers", [
        ("BT_ACCOUNT_PASSWORD", PASSWORD), ("BT_SSH_HOST", SSH_HOST), ("BT_SSH_PORT", ports.ssh),
        ("BT_ENDUSER_PORT", ports.enduser), ("BT_PULL_PARTNER", bt + "_from"), ("BT_PUSH_PARTNER", bt + "_to"),
        ("BT_STEP_PAUSE_SECONDS", "5"), ("BT_WAIT_SECONDS", "60")],
        [bt], [bt, bt + "_from", bt + "_to"], between=lambda folder: download(folder, bt))

    ar = TAG + "_ar"
    run_feature("trigger-route-after-completed-pull", "trigger-route-after-completed-pull", [
        ("AR_ACCOUNT_PASSWORD", PASSWORD), ("AR_SSH_HOST", SSH_HOST), ("AR_SSH_PORT", ports.ssh),
        ("AR_ENDUSER_PORT", ports.enduser), ("AR_PULL_SITE", ar + "PullSite"), ("AR_PUSH_SITE", ar + "PushSite"),
        ("AR_APPLICATION", ar + "App"), ("AR_TEMPLATE_ROUTE", ar + "Template"), ("AR_SIMPLE_ROUTE", ar + "Simple"),
        ("AR_COMPOSITE_ROUTE", ar + "Composite"), ("AR_STEP_PAUSE_SECONDS", "5"), ("AR_WAIT_SECONDS", "60")],
        [ar, "--cleanup"], [ar])
finally:
    admin.logout()
sys.exit(c.done())
