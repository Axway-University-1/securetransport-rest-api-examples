#!/usr/bin/env python3
"""
WRITES TO THE SERVER (two throwaway accounts, example_rsb_a and example_rsb_b, which it removes, and a few transfers that stay in the transfer log). Runs
Admin/UseCases/09-resubmit-transfers for real, as the administrator of the configuration.

It proves what the use case and its README say, through its own reads of the transfer log and not through the scripts. A whole run (00.run_all.sh) exits 0 and ends with the cleanup; each account
has six transfers after it, three flagged resubmitted and three new, for the API 2.0 account and for the API 1.4 account. Then it takes the steps one at a time to show the points of the README: a
second run of the 1.4 call resubmits the copies of the first (nine transfers, six flagged), the 1.4 script is refused without an ACCOUNT before any call, and after the accounts are deleted the
call answers ERROR for each entry (exit 1) and a 200 holds them. 99 can be run twice.

Needs --write and st_allow_writes="yes", and the End User port (st_enduser_port, or the admin port minus one). It does not run on the bundled mock, which has no transfer log of this kind.
"""
import datetime
import email.utils
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the resubmit use case for real")

c = st_client.Checker("Admin use case 09-resubmit-transfers, run for real")
ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
UC = runner.path("Admin", "UseCases", "09-resubmit-transfers")
STATE_FILES = ("session.cookie.jar", "state.local.csrf", "state.local.password", "state.local.window")
NAMES = ("example_rsb_a", "example_rsb_b")
ENV = {"ST_ENDUSER_PORT": harness.ports(config).enduser}

admin = harness.connect(config, c, mock="the bundled mock has no transfer log of this kind; run this against a real server to exercise it")


def clear_local():
    for leftover in STATE_FILES:
        p = os.path.join(UC, leftover)
        if os.path.exists(p):
            os.remove(p)


def accounts_there():
    return [n for n in NAMES if admin.exists("accounts/" + n)]


def rows(account, since):
    """(total, flagged) of the transfers of the account after `since` that are Processed, read from the log here. A new transfer is In Progress for a moment, and
    that is not one to resubmit yet: it is counted when it is done."""
    got = admin.results("logs/transfers", {"account": account, "startTimeAfter": since, "fields": "filename,status,resubmitted", "limit": 100})
    done = [t for t in got if t.get("status") == "Processed"]
    return len(done), len([t for t in done if t.get("resubmitted")])


def settled(account, since, total, flagged, seconds=40):
    """Wait for the log to hold `total` transfers with `flagged` of them flagged (a read the lab drops is read again); the last (total, flagged) seen."""
    harness.wait_until(lambda: rows(account, since) == (total, flagged), timeout=seconds, interval=1)
    return rows(account, since)


try:
    if accounts_there():
        c.info("accounts named example_rsb_* are on the server already (%s); skipping rather than reuse them" % ", ".join(accounts_there()))
        admin.logout()
        sys.exit(c.done())
    start = email.utils.format_datetime(datetime.datetime.now().astimezone() - datetime.timedelta(seconds=5))

    with runner.real_credentials(ADMIN_TREE, config):
        # -- a whole run --------------------------------------------------------------------------------------
        r = runner.run(os.path.join(UC, "00.run_all.sh"), timeout=300, env=ENV)
        c.check("00.run_all.sh exits 0", r.returncode == 0, (r.stdout + r.stderr).strip()[-600:])
        c.check("it ended with the cleanup", "Cleaned up." in r.stdout, r.stdout[-200:])
        c.check("and left no account and no state file", accounts_there() == [] and not any(os.path.exists(os.path.join(UC, f)) for f in STATE_FILES))
        for name, way in (("example_rsb_a", "2.0, one call for each transfer"), ("example_rsb_b", "1.4, one call")):
            c.check("%s (%s): six transfers in the log, three flagged resubmitted and three new" % (name, way), settled(name, start, 6, 3) == (6, 3), rows(name, start))
        c.check("2.0/02 resubmitted by the id of each transfer: three 'was successfully resubmitted'", r.stdout.count("HTTP 200, Transfer with id") == 3, r.stdout[:1500])
        c.check("1.4/02 resubmitted with one call: three OK entries and the totals", r.stdout.count("  OK: Transfer with id") == 3 and "HTTP 200: 3 entries, 3 OK, 0 not OK." in r.stdout, r.stdout[-1500:])
        c.check("2.0/01 shows what the id is made of", "...which is the Base64 of: Id [mTransferStatusId=" in r.stdout)

        # -- the points of the README -------------------------------------------------------------------------
        harness.wait_until(lambda: False, timeout=3, interval=1)   # past the last transfers of the run above
        again = email.utils.format_datetime(datetime.datetime.now().astimezone())
        steps = ("01.accounts_POST.sh", "02.uploads_POST.sh")
        for step in steps:
            r = runner.run(os.path.join(UC, step), timeout=180, env=ENV)
            c.check("%s exits 0" % step, r.returncode == 0, (r.stdout + r.stderr)[-400:])
        r = runner.run(os.path.join(UC, "1.4", "02.transfers_resubmit_POST.sh"), ["example_rsb_b"], timeout=120, env=ENV)
        c.check("1.4/02, the first run: exit 0, three OK", r.returncode == 0 and "3 entries, 3 OK" in r.stdout, r.stdout[-400:])
        c.check("... six transfers in the log, three flagged", settled("example_rsb_b", again, 6, 3) == (6, 3), rows("example_rsb_b", again))
        r = runner.run(os.path.join(UC, "1.4", "02.transfers_resubmit_POST.sh"), ["example_rsb_b"], timeout=120, env=ENV)
        c.check("1.4/02, a second run: exit 0 again, it resubmits the copies of the first", r.returncode == 0 and "3 entries, 3 OK" in r.stdout, r.stdout[-400:])
        c.check("... nine transfers in the log, six flagged: resubmitted=false did not keep it away", settled("example_rsb_b", again, 9, 6) == (9, 6), rows("example_rsb_b", again))
        r = runner.run(os.path.join(UC, "1.4", "02.transfers_resubmit_POST.sh"), [], env=ENV)
        c.check("1.4/02 with no ACCOUNT: exit 2 and the usage, and nothing resubmitted", r.returncode == 2 and "Usage: ./02.transfers_resubmit_POST.sh ACCOUNT" in r.stdout and rows("example_rsb_b", again) == (9, 6), (r.returncode, r.stdout[-200:]))
        r = runner.run(os.path.join(UC, "1.4", "01.transfers_GET.sh"), ["example_rsb_a"], env=ENV)
        c.check("1.4/01 previews the criteria: example_rsb_a has three transfers that were not resubmitted", r.returncode == 0 and "would touch 3 transfers:" in r.stdout, r.stdout[-300:])

        r = runner.run(os.path.join(UC, "99.cleanup_DELETE.sh"), timeout=120, env=ENV)
        c.check("99: exit 0, and no account is left", r.returncode == 0 and accounts_there() == [], (r.returncode, accounts_there(), r.stdout[-300:]))
        r = runner.run(os.path.join(UC, "99.cleanup_DELETE.sh"), timeout=120, env=ENV)
        c.check("99 a second time, with nothing to remove, exits 0", r.returncode == 0 and "was not there." in r.stdout, r.stdout[-300:])

        # -- the transfers of a deleted account ---------------------------------------------------------------
        r = runner.run(os.path.join(UC, "1.4", "02.transfers_resubmit_POST.sh"), ["example_rsb_a"], timeout=120, env=ENV)
        c.check("1.4/02 on the transfers of a deleted account: exit 1, ERROR entries in a 200", r.returncode == 1 and "  ERROR: Error while resubmitting transfer" in r.stdout, (r.returncode, r.stdout[-500:]))
        clear_local()
finally:
    for name in NAMES:
        if admin.exists("accounts/" + name):
            admin.delete("accounts/" + name)
    c.check("no account named example_rsb_* is left on the server", accounts_there() == [], accounts_there())
    clear_local()
    admin.logout()

sys.exit(c.done())
