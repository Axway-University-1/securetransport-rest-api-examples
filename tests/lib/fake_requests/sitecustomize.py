"""
Loaded by every python process that has tests/lib/fake_requests on PYTHONPATH,
the spawned workers of a multiprocessing example included.

FAKE_ST_START_METHOD names the multiprocessing start method (spawn, fork, forkserver) for the
process and for the workers it starts.

FAKE_ST_FAST=1 makes time.sleep return at once and advance a fake clock, so a
loop that waits and gives up after a timeout can be run in a fraction of a
second. The seconds it was asked to sleep are appended to FAKE_ST_LOG.
"""
import json
import os
import time

if os.environ.get("FAKE_ST_START_METHOD"):
    import multiprocessing
    multiprocessing.set_start_method(os.environ["FAKE_ST_START_METHOD"], force=True)

if os.environ.get("FAKE_ST_FAST") == "1":
    _real_time, _real_monotonic = time.time, time.monotonic
    _offset = [0.0]

    def _sleep(seconds):
        _offset[0] += float(seconds)
        path = os.environ.get("FAKE_ST_LOG")
        if path:
            with open(path, "a") as f:
                f.write(json.dumps({"sleep": float(seconds)}) + "\n")

    time.sleep = _sleep
    time.time = lambda: _real_time() + _offset[0]
    time.monotonic = lambda: _real_monotonic() + _offset[0]
