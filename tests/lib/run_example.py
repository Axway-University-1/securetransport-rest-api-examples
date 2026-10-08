#!/usr/bin/env python3
"""
Run a python example, as a person would, against the in-memory fake SecureTransport.

fake_st.py runs single functions out of an example. This runs the whole script as
a separate process, main block included, with tests/lib/fake_requests first on
PYTHONPATH, so `import requests` finds the stand-in. It is the only way to see an
exit code, a traceback, a spawned worker process or what the script does when the
server answers 500, and it is how a missing csrfToken header shows: the stand-in
refuses a write that has none.

    from run_example import run
    result = run("stDeleteTestAccounts.py", ["--apply"], scenario={"collections": {...}})
    result.returncode, result.output, result.calls, result.writes()

The script is copied into a temporary folder first, next to a config file written
for the test, so nothing it writes (logs, baselines, key files) lands in the repository.
Nothing here touches the network.
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
# EXAMPLES_PYTHON_DIR points the tests at another copy of the python folder, for instance
# a checkout of an older commit, to see that a test fails on the code it was written against
PYTHON_DIR = os.environ.get("EXAMPLES_PYTHON_DIR") or os.path.join(HERE, "..", "..", "Admin", "API 2.0", "python")
FAKE_REQUESTS = os.path.join(HERE, "fake_requests")

CONFIG = {"st_server": "st.example.com", "st_port": "8444", "st_user": "apiadmin",
          "st_password": "not-a-real-password"}


class Result:
    def __init__(self, returncode, output, entries, snapshot):
        self.returncode = returncode
        self.output = output
        self.entries = entries
        self._snapshot = snapshot    # {folder name: {file name: (bytes, mode)}}, taken before the folder is removed
        self.timed_out = False

    @property
    def calls(self):
        return [e for e in self.entries if "method" in e]

    @property
    def sleeps(self):
        return [e["sleep"] for e in self.entries if "sleep" in e]

    def writes(self, include_session=False):
        """The POST, PUT, PATCH and DELETE calls, the login and logout left out unless asked."""
        return [e for e in self.calls if e["method"] in ("POST", "PUT", "PATCH", "DELETE")
                and (include_session or e["path"] != "myself")]

    def violations(self):
        return [(e["method"], e["path"], e["violation"]) for e in self.calls if "violation" in e]

    def read(self, name, where="cwd"):
        """The bytes of a file the script left in the folder it started in (where="cwd") or beside itself ("script")."""
        found = self._snapshot.get(where, {}).get(name)
        return found[0] if found else None

    def mode(self, name, where="cwd"):
        found = self._snapshot.get(where, {}).get(name)
        return found[1] if found else None


def _snapshot(folder):
    out = {}
    for name in os.listdir(folder):
        p = os.path.join(folder, name)
        if os.path.isfile(p):
            out[name] = (open(p, "rb").read(), os.stat(p).st_mode & 0o777)
    return out


def run(script, args=(), scenario=None, config=None, files=None, fast=False, timeout=40, env=None, edits=None, tree_files=None, start_method=None):
    """
    Run <script>, a path under python/python3 ("../utils/x.py" reaches the utils) and return a Result.

    scenario  what the fake server holds and how it misbehaves, see requests/_server.py
    config    values for the config file, on top of CONFIG; None as a value leaves a key out; False writes no config file
    files     {name: text or bytes} written to the folder the script starts in
    fast      sleeping returns at once and moves a fake clock on
    env       more environment variables for the script
    edits     {old text: new text} applied to the copy of the script, as the integration checks do
    tree_files {path under python/: text or bytes} written into the copy of the folder, next to the config
    start_method  "spawn", "fork" or "forkserver": how multiprocessing starts a worker. Left out it is the
              platform's own, which is what a person gets; "spawn" is the strict one (macOS, Windows,
              and Linux from Python 3.14) and finds a worker that relies on what only the parent set up
    """
    workdir = tempfile.mkdtemp(prefix="fakest_")
    try:
        tree = os.path.join(workdir, "python")
        shutil.copytree(PYTHON_DIR, tree, ignore=shutil.ignore_patterns(
            "__pycache__", "ssl", "*.pem", "*.crt", "*.log", "compareXML*"))
        values = dict(CONFIG)
        values.update(config or {})
        if config is not False:
            with open(os.path.join(tree, "config"), "w") as f:
                f.write("".join('%s="%s"\n' % (k, v) for k, v in values.items() if v is not None))
        cwd = os.path.join(workdir, "cwd")
        os.makedirs(cwd)
        for name, content in (files or {}).items():
            with open(os.path.join(cwd, name), "wb" if isinstance(content, bytes) else "w") as f:
                f.write(content)
        for name, content in (tree_files or {}).items():
            target = os.path.join(tree, name)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb" if isinstance(content, bytes) else "w") as f:
                f.write(content)
        scenario_file = os.path.join(workdir, "scenario.json")
        with open(scenario_file, "w") as f:
            json.dump(scenario or {}, f)
        log_file = os.path.join(workdir, "calls.log")

        environment = dict(os.environ)
        for k in list(environment):
            if k.startswith("ST_") or k.startswith("FAKE_ST"):
                del environment[k]
        environment.update({
            "PYTHONPATH": FAKE_REQUESTS,
            "FAKE_ST_SCENARIO": scenario_file,
            "FAKE_ST_LOG": log_file,
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONUNBUFFERED": "1",
        })
        if fast:
            environment["FAKE_ST_FAST"] = "1"
        if start_method:
            environment["FAKE_ST_START_METHOD"] = start_method
        environment.update(env or {})

        script_path = os.path.normpath(os.path.join(tree, "python3", script))
        if edits:
            text = open(script_path).read()
            for old, new in edits.items():
                if old not in text:
                    raise AssertionError("the edit %r finds nothing in %s" % (old, script))
                text = text.replace(old, new)
            open(script_path, "w").write(text)
        process = subprocess.Popen(
            [sys.executable, script_path] + list(args), cwd=cwd, env=environment,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            start_new_session=True)     # no controlling terminal: a prompt cannot reach the person running the tests
        timed_out = False
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            # a loop that does not end: stop it and its workers, and say so
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
            output = (output or "") + "\nTIMED OUT after %s seconds, a loop that does not end\n" % timeout
        entries = []
        if os.path.exists(log_file):
            for line in open(log_file):
                line = line.strip()
                if line:
                    entries.append(json.loads(line))
        snapshot = {"cwd": _snapshot(cwd), "script": _snapshot(os.path.dirname(script_path))}
        result = Result(process.returncode, output, entries, snapshot)
        result.timed_out = timed_out
        return result
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
