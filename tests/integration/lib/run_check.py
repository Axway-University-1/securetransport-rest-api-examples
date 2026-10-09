#!/usr/bin/env python3
"""
Run one integration check with a time limit: `run_check.py CHECK.py [ARGS...]`.

run_integration.sh runs the checks one after another, and a check that hangs (a server that accepts the
connection and never answers, an example waiting for input, a loop that cannot end) used to hang the whole run.
macOS has no `timeout` command, so the limit is kept here, in python, which both it and Linux have.

  ST_CHECK_TIMEOUT       seconds a check may run, 1800 (half an hour) when not set. The longest check, 59, takes
                         about five minutes on the lab. 0 or "none" turns the limit off.
  ST_CHECK_GRACE         seconds a check gets to clean up after it was asked to stop, 120 when not set.

When the limit passes, the check's whole process group (the check and the curl, bash and sftp processes it
started) gets SIGTERM, which script_runner turns into an exit that runs the check's `finally` blocks, so the
throwaway objects are still removed. A check that is still running after the grace period gets SIGKILL.
The exit status is 124 (as with timeout(1)) and a FAIL line says why, in the output of the check, which is where
run_integration.sh reads the verdict from. In every other case the exit status is the check's own.

A SIGINT or SIGTERM sent to this process is passed on to the check, which is in a group of its own.
"""
import os
import signal
import subprocess
import sys
import time

DEFAULT_TIMEOUT = 1800.0
DEFAULT_GRACE = 120.0
TIMED_OUT = 124


def seconds(name, default):
    """The number of seconds in the environment variable, `default` when it is blank or not a number, None for 0 / none (no limit)."""
    raw = (os.environ.get(name) or "").strip().lower()
    if not raw:
        return default
    if raw in ("0", "none", "off", "no"):
        return None
    try:
        value = float(raw)
    except ValueError:
        print("  ..    %s=%r is not a number of seconds: using %d" % (name, raw, default), flush=True)
        return default
    return value if value > 0 else None


def stop_group(proc, signum):
    try:
        os.killpg(proc.pid, signum)
    except (ProcessLookupError, PermissionError):
        pass


def main(argv):
    if len(argv) < 2:
        print("usage: run_check.py CHECK.py [ARGS...]", file=sys.stderr)
        return 2
    limit = seconds("ST_CHECK_TIMEOUT", DEFAULT_TIMEOUT)
    grace = seconds("ST_CHECK_GRACE", DEFAULT_GRACE) or DEFAULT_GRACE
    proc = subprocess.Popen([sys.executable] + argv[1:], start_new_session=True)

    def forward(signum, frame):
        stop_group(proc, signum)
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, forward)

    started = time.time()
    while True:
        try:
            return proc.wait(timeout=0.5 if limit is None else max(0.01, min(0.5, limit - (time.time() - started))))
        except subprocess.TimeoutExpired:
            if limit is not None and time.time() - started >= limit:
                break
    name = os.path.basename(argv[1])
    print("", flush=True)
    print("  FAIL  %s did not finish within %d seconds (ST_CHECK_TIMEOUT) and was stopped: it was sent SIGTERM so that it removes what it made, "
          "and gets %d seconds for that" % (name, limit, grace), flush=True)
    stop_group(proc, signal.SIGTERM)
    try:
        proc.wait(timeout=grace)
        print("  ..    %s ended %d seconds after SIGTERM" % (name, time.time() - started - limit), flush=True)
    except subprocess.TimeoutExpired:
        stop_group(proc, signal.SIGKILL)
        proc.wait()
        print("  FAIL  %s was still running %d seconds after SIGTERM and was killed (SIGKILL): look for what it left on the server" % (name, grace),
              flush=True)
    return TIMED_OUT


if __name__ == "__main__":
    sys.exit(main(sys.argv))
