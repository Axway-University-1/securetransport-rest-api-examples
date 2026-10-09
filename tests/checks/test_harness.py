#!/usr/bin/env python3
"""
The shared harness of the integration checks (tests/integration/lib/harness.py), without a server.

Each of these was a copy in a dozen checks before, and the copies drifted: a wait loop that did not catch a refused
connection crashed a check the day the lab restarted a daemon, a gate that was not repeated ran a write. They are
here once, so they are tested once, here: the wait (a refused call is "not yet", the last value comes back, the
time is bounded), the ports (the config, then the servers the Admin API lists, then the default), the run of an
example (the exit code is checked and named, the environment is only for that run, a lookup that came back empty
is run again), the gate for --write, and the throwaway account (a fresh name and user id, its files and then
itself deleted, whatever happened inside the block).

Also that no check carries its own copy again.

Runs offline. Exit code 0 means clean.
"""
import contextlib
import glob
import io
import os
import re
import sys
import tempfile
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tests", "integration", "lib"))
import harness  # noqa: E402
import st_client  # noqa: E402

failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1


class FakeTime:
    """A clock that only moves when something sleeps, so a wait of a minute takes no time."""

    def __init__(self):
        self.now = 1000.0
        self.slept = []

    def time(self):
        return self.now

    def sleep(self, seconds):
        self.slept.append(seconds)
        self.now += seconds


class Recorder:
    """Stands for the Checker of a check."""

    def __init__(self):
        self.checks, self.infos = [], []

    def check(self, label, condition, detail=""):
        self.checks.append((label, bool(condition), detail))
        return bool(condition)

    def info(self, message):
        self.infos.append(message)

    def done(self):
        return 0 if all(ok for _, ok, _ in self.checks) else 1


real_time = harness.time
clock = FakeTime()
harness.time = clock

print("=== wait_until ===")
calls = []
check("a predicate that is true at once is asked once and does not sleep",
      harness.wait_until(lambda: calls.append(1) or True, 30) is True and len(calls) == 1 and clock.slept == [], (calls, clock.slept))

answers = iter([False, False, "ready"])
check("it asks again until true and gives back the value that was true",
      harness.wait_until(lambda: next(answers), 30, 2) == "ready" and clock.slept == [2, 2], clock.slept)

clock.slept.clear()
start = clock.now
value = harness.wait_until(lambda: [], 10, 3)
check("a predicate that never holds gives up after the timeout, not before, and returns its last value",
      value == [] and clock.now - start == 10 and clock.slept == [3, 3, 3, 1], (value, clock.now - start, clock.slept))

clock.slept.clear()
seen = []


def refused_then_up():
    seen.append(1)
    if len(seen) < 3:
        raise st_client.STError("cannot reach the server: connection refused")
    return {"daemon": "running"}


check("a refused or unanswered call (STError) is one more not yet, and the wait goes on to the answer",
      harness.wait_until(refused_then_up, 30, 1) == {"daemon": "running"} and len(seen) == 3, len(seen))


def never_up():
    raise st_client.STError("no answer")


check("a server that stays unreachable ends in the timeout with None, not a crash", harness.wait_until(never_up, 5, 1) is None)

try:
    harness.wait_until(lambda: 1 / 0, 5, 1)
    boom = None
except ZeroDivisionError:
    boom = "ZeroDivisionError"
check("only STError is caught: a mistake in the check itself still stops it", boom == "ZeroDivisionError", boom)

clock.slept.clear()
late = iter([False] * 3 + ["just in time"])
check("it asks one last time at the deadline", harness.wait_until(lambda: next(late), 3, 1) == "just in time", clock.slept)

print("=== settled ===")
reads = iter([{"n": 1}, {"n": 2}, {"n": 3}])
check("settled polls a read until the condition holds and returns that value",
      harness.settled(lambda: next(reads), lambda v: v["n"] == 2, 30, 1) == {"n": 2})
check("and when it never holds, the last value read, so the check can show it",
      harness.settled(lambda: {"n": 0}, lambda v: v["n"] == 9, 3, 1) == {"n": 0})
check("an object that cannot be read at all is None", harness.settled(lambda: None, lambda v: True, 3, 1) is None)
check("a read that fails with STError is waited out", harness.settled(iter([None, {"ok": 1}]).__next__, lambda v: True, 5, 1) == {"ok": 1})

harness.time = real_time

print("=== ports ===")
SERVERS = [
    {"protocol": "as2", "isActive": False},
    {"protocol": "ftp", "port": 8021, "isActive": True},
    {"protocol": "pesit", "pesitPort": 17617, "isActive": True},
    {"protocol": "ssh", "port": 8030, "isActive": False},
    {"protocol": "ssh", "port": 8022, "isActive": True},
    {"protocol": "http", "httpsPort": 8443, "isActive": True},
]


class FakeResponse:
    def __init__(self, status=200, body=None):
        self.status, self.body, self.text = status, body, str(body)[:200]
        self.headers = {}

    def json(self):
        return self.body


class FakeAdmin:
    """Answers GET /servers and records every call; accounts it is asked to create are kept."""

    def __init__(self, servers=None, create_status=201, delete_status=204):
        self.servers, self.calls = servers, []
        self.create_status, self.delete_status = create_status, delete_status
        self.accounts = {}

    def get(self, path, params=None):
        self.calls.append(("GET", path))
        if path == "servers":
            return FakeResponse(200, self.servers)
        return FakeResponse(404, None)

    def post(self, path, body, params=None):
        self.calls.append(("POST", path, body))
        if path == "accounts" and self.create_status == 201:
            self.accounts[body["name"]] = body
        return FakeResponse(self.create_status, {})

    def delete(self, path, params=None):
        self.calls.append(("DELETE", path))
        if isinstance(self.delete_status, Exception):
            raise self.delete_status
        if path.startswith("accounts/"):
            self.accounts.pop(path.split("/", 1)[1], None)
        return FakeResponse(self.delete_status, "")


CONFIG = {"st_server": "lab.example", "st_port": "444"}
check("with nothing in the config and no admin: the admin port minus one, 8022, 17617 and no FTP",
      (lambda p: (p.enduser, p.ssh, p.pesit, p.ftp))(harness.ports(CONFIG)) == ("443", "8022", "17617", None))
p = harness.ports(CONFIG, FakeAdmin(SERVERS))
check("without the config the ports of the running servers the Admin API lists: a stopped ssh server listed first is passed over",
      (p.ssh, p.ftp, p.pesit) == ("8022", "8021", "17617"), p)
p = harness.ports(CONFIG, FakeAdmin({"result": SERVERS}))
check("GET /servers answered as {result: [...]} is read the same way", (p.ssh, p.ftp) == ("8022", "8021"), p)
p = harness.ports(dict(CONFIG, st_enduser_port="8443", st_ssh_port="2222", st_pesit_port="9999"), FakeAdmin(SERVERS))
check("the config wins over what the server lists", (p.enduser, p.ssh, p.pesit, p.ftp) == ("8443", "2222", "9999", "8021"), p)
p = harness.ports(dict(CONFIG, st_enduser_port="", st_ssh_port="", st_pesit_port=""), FakeAdmin(SERVERS))
check("a blank value in the config counts as not named (the example file leaves them blank)", (p.enduser, p.ssh, p.pesit) == ("443", "8022", "17617"), p)
p = harness.ports(CONFIG, FakeAdmin([{"protocol": "ssh", "port": 8030, "isActive": False}]))
check("a server that is stopped is still the answer when it is the only one", p.ssh == "8030", p)
p = harness.ports(CONFIG, FakeAdmin(None))
check("an admin that cannot answer /servers leaves the defaults", (p.ssh, p.ftp, p.pesit) == ("8022", None, "17617"), p)
check("servers_list unwraps a plain array and a result object",
      harness.servers_list(FakeAdmin(SERVERS)) == SERVERS and harness.servers_list(FakeAdmin({"result": SERVERS})) == SERVERS)

print("=== run_script ===")
with tempfile.TemporaryDirectory() as work:
    def write(name, text):
        with open(os.path.join(work, name), "w") as f:
            f.write(text)
    write("echo.sh", 'echo "args: $*"; echo "err" >&2; exit "${RC:-0}"\n')
    write("env.sh", 'echo "[${EXAMPLE_VALUE:-unset}]"\n')
    write("flaky.sh", 'n=$(cat "$COUNTER" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$COUNTER"\n'
                      '[ "$n" -lt "$SUCCEED_AT" ] && echo "Found 0 sites named x" || echo "Found 1 sites named x"\n')
    rec = Recorder()
    out = harness.run_script(rec, work, "echo.sh", ["a", "b c"])
    check("it returns what the example printed, stdout and stderr", "args: a b c" in out and "err" in out, out)
    check("and names the check '<name> <args> exits <rc>', passing on exit 0",
          rec.checks == [("echo.sh a b c exits 0", True, rec.checks[0][2])], rec.checks)
    rec = Recorder()
    harness.run_script(rec, work, "echo.sh", [], expect_rc=3, env={"RC": "3"})
    check("an expected non zero exit code passes, and one that is not the expected fails", rec.checks[0][1] is True)
    harness.run_script(rec, work, "echo.sh", [], expect_rc=0, env={"RC": "1"})
    check("a wrong exit code is a failed check that shows the output", rec.checks[1][1] is False and "args:" in rec.checks[1][2], rec.checks[1])
    harness.run_script(rec, work, "echo.sh", [], expect_rc=(0, 1), env={"RC": "1"})
    check("several exit codes can be right, and are named with 'or'", rec.checks[2][1] is True and rec.checks[2][0] == "echo.sh  exits 0 or 1", rec.checks[2])
    n = len(rec.checks)
    harness.run_script(rec, work, "echo.sh", [], expect_rc=None, env={"RC": "9"})
    check("expect_rc=None asks for no check", len(rec.checks) == n)
    harness.run_script(rec, work, "echo.sh", ["x" * 50, "y"], arg_width=5)
    check("arg_width cuts each argument in the name", rec.checks[-1][0] == "echo.sh xxxxx y exits 0", rec.checks[-1][0])
    harness.run_script(rec, work, "echo.sh", ["q"], label="{name} runs")
    check("a label with {name} replaces the default", rec.checks[-1][0] == "echo.sh runs", rec.checks[-1][0])
    harness.run_script(rec, work, "echo.sh", ["z" * 400], tail=20)
    check("tail limits the output kept for a failure", len(rec.checks[-1][2]) <= 20, len(rec.checks[-1][2]))

    rec = Recorder()
    os.environ.pop("EXAMPLE_VALUE", None)
    out = harness.run_script(rec, work, "env.sh", env={"EXAMPLE_VALUE": "from the check"})
    check("env reaches the example", "[from the check]" in out, out)
    check("and is not left in this process's environment", "EXAMPLE_VALUE" not in os.environ)
    check("a variable already set is not changed for the next run either",
          harness.run_script(rec, work, "env.sh").strip() == "[unset]")

    counter = os.path.join(work, "counter")
    harness.time = FakeTime()      # the pause between two runs costs no time
    rec = Recorder()
    out = harness.run_script(rec, work, "flaky.sh", env={"COUNTER": counter, "SUCCEED_AT": "3"}, retry_text="Found 0 sites named", retry_delay=0)
    check("a lookup that found nothing is run again until it finds it",
          "Found 1 sites named" in out and open(counter).read().strip() == "3" and len(rec.checks) == 1, out)
    os.remove(counter)
    out = harness.run_script(rec, work, "flaky.sh", env={"COUNTER": counter, "SUCCEED_AT": "99"}, retry_text="Found 0 sites named", retries=4, retry_delay=0)
    check("and gives up after `retries` runs, showing the last answer", "Found 0 sites named" in out and open(counter).read().strip() == "4", out)
    os.remove(counter)
    script = harness.bind_script(rec, work, retry_text="Found 0 sites named")
    script("flaky.sh", env={"COUNTER": counter, "SUCCEED_AT": "99"}, retry=False)
    check("bind_script's retry=False runs it once", open(counter).read().strip() == "1")
    harness.time = real_time

print("=== the gate for --write ===")


def gate(config, argv, what="run the x examples for real"):
    """(did it return, what it printed): the skip is an exit 0, as in a check."""
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stdout(buffer):
            harness.require_writes(config, what, argv=argv)
        return True, buffer.getvalue()
    except SystemExit as e:
        return (False if e.code == 0 else None), buffer.getvalue()


ok, text = gate(None, ["x.py", "--write"])
check("no config: skip", ok is False and "no tests/local/integration.conf" in text, text)
ok, text = gate({"st_allow_writes": "yes"}, ["x.py"])
check("no --write: skip, saying what --write would run", ok is False and "pass --write to run the x examples for real" in text, text)
ok, text = gate({"st_allow_writes": "no"}, ["x.py", "--write"])
check("--write without st_allow_writes in the config: skip", ok is False and "st_allow_writes" in text, text)
ok, text = gate({}, ["x.py", "--write"])
check("--write and a config that does not mention st_allow_writes: skip", ok is False, text)
for value in ("yes", "YES", "true", "1"):
    ok, text = gate({"st_allow_writes": value}, ["x.py", "--write"])
    check("--write and st_allow_writes=%s: it goes on" % value, ok is True and text == "", text)
check("writes_allowed says the same", harness.writes_allowed({"st_allow_writes": "yes"}, ["x", "--write"]) is True
      and harness.writes_allowed({"st_allow_writes": "yes"}, ["x"]) is False
      and harness.writes_allowed({"st_allow_writes": "no"}, ["x", "--write"]) is False and harness.writes_allowed(None, ["x", "--write"]) is False)

print("=== connect and the mock ===")
real_connect, real_is_mock = st_client.connect, st_client.is_mock


class Client:
    logged_out = False

    def logout(self):
        self.logged_out = True


client = Client()
st_client.connect = lambda config, c: client
try:
    st_client.is_mock = lambda cl: True
    rec = Recorder()
    try:
        harness.connect({}, rec, mock="the bundled mock does not implement /x")
        code = "returned"
    except SystemExit as e:
        code = e.code
    check("on the mock, a check that says why it cannot run there ends: its reason shown, logged out, exit 0 (a skip)",
          code == 0 and rec.infos == ["the bundled mock does not implement /x"] and client.logged_out, (code, rec.infos))
    st_client.is_mock = lambda cl: False
    client.logged_out = False
    check("on a real server it returns the logged in client", harness.connect({}, Recorder(), mock="x") is client and not client.logged_out)
    st_client.is_mock = lambda cl: True
    check("a check with no `mock` reason runs on the mock too", harness.connect({}, Recorder()) is client)
finally:
    st_client.connect, st_client.is_mock = real_connect, real_is_mock

print("=== a throwaway account ===")


class FakeEndUser:
    """Stands for EndUserClient: a home folder with files and folders, a login that works or not, and a log of what it deleted."""
    tree = {}
    login_status = 200
    deleted = []
    instances = []

    def __init__(self, host, port, user, password, **kw):
        self.host, self.port, self.user, self.password = host, port, user, password
        FakeEndUser.instances.append(self)

    def login_response(self):
        return FakeResponse(FakeEndUser.login_status, {})

    def logout(self):
        return FakeResponse(204, "")

    def list_files(self, params=None):
        return self._request("GET", "files")

    def _request(self, method, path, headers=None, data=None):
        folder = urllib.parse.unquote(path[len("files"):].strip("/"))
        node = FakeEndUser.tree
        for part in [p for p in folder.split("/") if p]:
            node = node.get(part)
            if not isinstance(node, dict):
                return FakeResponse(404, {})
        return FakeResponse(200, {"files": [{"fileName": k, "isDirectory": isinstance(v, dict), "isRegularFile": not isinstance(v, dict)}
                                            for k, v in node.items()]})

    def delete_file(self, path):
        path = urllib.parse.unquote(path)
        FakeEndUser.deleted.append(path)
        parts = path.split("/")
        node = FakeEndUser.tree
        for part in parts[:-1]:
            node = node[part]
        if isinstance(node.get(parts[-1]), dict) and node[parts[-1]]:
            return FakeResponse(409, {})
        node.pop(parts[-1], None)
        return FakeResponse(204, "")


def reset_enduser(tree):
    FakeEndUser.tree, FakeEndUser.login_status, FakeEndUser.deleted, FakeEndUser.instances = tree, 200, [], []


reset_enduser({"a.txt": b"", "in": {"b.txt": b"", "deep": {"c.txt": b""}}, "out": {}})
admin = FakeAdmin()
rec = Recorder()
with harness.throwaway_account(admin, rec, CONFIG, prefix="example_t", enduser_factory=FakeEndUser) as account:
    inside = (account.name, account.uid, account.password, account.created)
    check("the account is created through the Admin API with its own name, a uid as gid, a home folder under /home and the password",
          account.name in admin.accounts and admin.accounts[account.name]["homeFolder"] == "/home/" + account.name
          and admin.accounts[account.name]["uid"] == str(account.uid) == admin.accounts[account.name]["gid"]
          and admin.accounts[account.name]["user"]["passwordCredentials"]["password"] == account.password, admin.accounts)
    check("the name carries the prefix and random letters, and the set up is a passed check",
          re.fullmatch(r"example_t_[a-z0-9]{6}", account.name) and rec.checks == [("set up: the account " + account.name, True, rec.checks[0][2])], rec.checks)
    check("the password is one the server's rules accept (letters, digits, a symbol)",
          len(account.password) >= 12 and re.search(r"[A-Z]", account.password) and re.search(r"[a-z]", account.password)
          and re.search(r"\d", account.password) and re.search(r"[^A-Za-z0-9]", account.password), account.password)
first_folder = min(i for i, p in enumerate(FakeEndUser.deleted) if p in ("in", "out", "in/deep"))
check("when the block ends every file is deleted before any folder, and a folder below another before it, then the account",
      sorted(FakeEndUser.deleted[:first_folder]) == ["a.txt", "in/b.txt", "in/deep/c.txt"]
      and set(FakeEndUser.deleted[first_folder:]) == {"in/deep", "in", "out"}
      and FakeEndUser.deleted.index("in/deep") < FakeEndUser.deleted.index("in"), FakeEndUser.deleted)
check("... the home folder is empty, and the account is gone", FakeEndUser.tree == {} and inside[0] not in admin.accounts, (FakeEndUser.tree, admin.accounts))
check("it logged in as the account, on the EndUser port",
      FakeEndUser.instances and FakeEndUser.instances[0].user == inside[0] and FakeEndUser.instances[0].port == "443"
      and FakeEndUser.instances[0].password == inside[2], FakeEndUser.instances and vars(FakeEndUser.instances[0]))

reset_enduser({"x.txt": b""})
admin = FakeAdmin()
try:
    with harness.throwaway_account(admin, Recorder(), CONFIG, enduser_factory=FakeEndUser) as account:
        name = account.name
        raise RuntimeError("the check failed half way")
except RuntimeError:
    pass
check("an exception inside the block still removes the files and the account, and goes on up", name not in admin.accounts and FakeEndUser.tree == {})

names, uids = set(), set()
admin = FakeAdmin()
for _ in range(30):
    reset_enduser({})
    with harness.throwaway_account(admin, Recorder(), CONFIG, enduser_factory=FakeEndUser) as account:
        names.add(account.name)
        uids.add(account.uid)
check("every account has a name and a user id that no other has had (a home folder keeps the first uid)", len(names) == 30 and len(uids) == 30, (len(names), len(uids)))

reset_enduser({"keep.txt": b""})
FakeEndUser.login_status = 401
admin = FakeAdmin()
with harness.throwaway_account(admin, Recorder(), CONFIG, enduser_factory=FakeEndUser) as account:
    pass
check("an account that cannot log in is still deleted (the files stay, and it says so)",
      account.name not in admin.accounts and FakeEndUser.deleted == [] and any("could not log in" in n for n in account.notes), account.notes)

reset_enduser({})
admin = FakeAdmin(delete_status=st_client.STError("no answer"))
rec = Recorder()
with harness.throwaway_account(admin, rec, CONFIG, enduser_factory=FakeEndUser) as account:
    pass
check("a delete that cannot reach the server is not a crash; the check is told by name to remove the account by hand",
      any(account.name in i and "by hand" in i for i in rec.infos), rec.infos)
admin = FakeAdmin(delete_status=500)
rec = Recorder()
with harness.throwaway_account(admin, rec, CONFIG, enduser_factory=FakeEndUser) as account:
    pass
check("a delete the server refuses is told the same way", any(account.name in i and "500" in i for i in rec.infos), rec.infos)

admin = FakeAdmin(create_status=409)
rec = Recorder()
FakeEndUser.instances = []
try:
    with harness.throwaway_account(admin, rec, CONFIG, enduser_factory=FakeEndUser):
        entered = True
except SystemExit as e:
    entered = ("stopped", e.code)
check("an account that cannot be created fails the check and stops it, and nothing is deleted (it is not ours)",
      entered == ("stopped", 1) and rec.checks[0][1] is False and not [call for call in admin.calls if call[0] == "DELETE"] and FakeEndUser.instances == [],
      (entered, rec.checks, admin.calls))

reset_enduser({})
admin = FakeAdmin()
with harness.throwaway_account(admin, Recorder(), CONFIG, name="example_given", home="/bu/example_given", extra={"businessUnit": "bu"},
                               label="set up: an account in that unit", password="pw", enduser_factory=FakeEndUser) as account:
    body = admin.accounts["example_given"]
check("a name, a home folder, more fields and a label can be given", body["homeFolder"] == "/bu/example_given" and body["businessUnit"] == "bu"
      and body["user"]["passwordCredentials"]["password"] == "pw" and account.name == "example_given", body)

reset_enduser({"my file.txt": b"", "a b": {"c d.txt": b""}})
admin = FakeAdmin()
with harness.throwaway_account(admin, Recorder(), CONFIG, enduser_factory=FakeEndUser) as account:
    pass
check("a name with a space is deleted too (it is quoted in the path)", FakeEndUser.tree == {} and "a b/c d.txt" in FakeEndUser.deleted, (FakeEndUser.tree, FakeEndUser.deleted))


class BrokenEndUser(FakeEndUser):
    def login_response(self):
        raise ValueError("URL can't contain control characters")


reset_enduser({})
admin = FakeAdmin()
with harness.throwaway_account(admin, Recorder(), CONFIG, enduser_factory=BrokenEndUser) as account:
    pass
check("whatever goes wrong while the files are removed, the account is still deleted and the check goes on",
      account.name not in admin.accounts and any("could not remove the files" in n for n in account.notes), account.notes)

print("=== a temporary folder is removed however the check ends ===")
import signal  # noqa: E402
import subprocess  # noqa: E402
LIB = os.path.join(REPO, "tests", "integration", "lib")
DRIVER = ("import os, sys, time\nsys.path.insert(0, %r)\nimport harness\npath = harness.scratch('harness_test_')\n"
          "open(os.path.join(path, 'f'), 'w').write('x')\nprint(path, flush=True)\n" % LIB)
for label, tail in (("ends normally", ""), ("ends with sys.exit(1)", "sys.exit(1)\n"), ("raises", "raise RuntimeError('boom')\n")):
    run = subprocess.run([sys.executable, "-c", DRIVER + tail], capture_output=True, text=True)
    folder = run.stdout.strip()
    check("a check that %s leaves no folder behind" % label, folder and not os.path.exists(folder), (folder, run.stderr[-200:]))
proc = subprocess.Popen([sys.executable, "-c", DRIVER + "time.sleep(60)\n"], stdout=subprocess.PIPE, text=True)
folder = proc.stdout.readline().strip()
check("while it runs the folder is there", os.path.isdir(folder), folder)
proc.send_signal(signal.SIGTERM)       # what the runner's time limit sends
proc.wait(timeout=20)
check("and a SIGTERM (the runner's time limit) removes it too", not os.path.exists(folder), folder)

print("=== what run_script returns ===")
with tempfile.TemporaryDirectory() as work:
    with open(os.path.join(work, "rc.sh"), "w") as f:
        f.write('echo "said"; exit 7\n')
    out = harness.run_script(Recorder(), work, "rc.sh", expect_rc=None)
    check("the output is text that also carries the exit code", out.strip() == "said" and out.returncode == 7 and isinstance(out, str), (out, out.returncode))
    rec = Recorder()
    harness.run_script(rec, work, "rc.sh", ["a", "b"], expect_rc=7, label=lambda name, shown, rc: "01 %s exits %s" % (shown or "with no arguments", rc))
    harness.run_script(rec, work, "rc.sh", [], expect_rc=7, label=lambda name, shown, rc: "01 %s exits %s" % (shown or "with no arguments", rc))
    check("a label can be a function of the name, the arguments and the exit code",
          [r[0] for r in rec.checks] == ["01 a b exits 7", "01 with no arguments exits 7"], rec.checks)
    rec = Recorder()
    harness.run_script(rec, work, "rc.sh", ["secret", "x"], expect_rc=7, hide=("secret",))
    check("an argument given as hidden (a password) is not in the name of the check", rec.checks[0][0] == "rc.sh x exits 7", rec.checks)

print("=== random text ===")
check("new_password is different each time", len({harness.new_password() for _ in range(20)}) == 20)
check("suffix is lowercase letters and digits of the length asked", re.fullmatch(r"[a-z0-9]{8}", harness.suffix(8)) is not None)
ids = {harness.fresh_uid() for _ in range(200)}
check("fresh_uid never gives the same user id twice", len(ids) == 200)

print("=== the checks use the shared pieces, none carries its own copy ===")
checks = sorted(glob.glob(os.path.join(REPO, "tests", "integration", "checks", "*.py")))
check("there are checks to read", len(checks) > 50, len(checks))
RULES = (
    ("defines its own wait_until or wait_for", re.compile(r"^def (wait_until|wait_for)\(", re.M)),
    ("defines its own create_account", re.compile(r"^def create_account\(", re.M)),
    ("works out the EndUser port itself", re.compile(r'config\.get\("st_enduser_port"\) or')),
    ("works out the SSH or PeSIT port itself", re.compile(r'config\.get\("st_(ssh|pesit)_port"\) or')),
    ("unwraps the servers list itself", re.compile(r'servers if isinstance\(servers, list\)')),
    ("repeats the --write gate", re.compile(r'"--write" not in sys\.argv')),
    ("makes a temporary folder it may never remove", re.compile(r"tempfile\.mkdtemp\(")),
    ("logs in to the EndUser API by hand", re.compile(r'"Authorization": "Basic " \+ \w+\._auth')),
    ("writes its own askpass for sftp or ssh", re.compile(r"SSH_ASKPASS\w*=")),
)
for name, pattern in RULES:
    offenders = [os.path.basename(p) for p in checks if pattern.search(open(p).read())]
    check("no check " + name, not offenders, offenders)

import ast  # noqa: E402


def sleeps_in_loops(source):
    """Line numbers of a time.sleep(...) of more than half a second inside a for or while loop: a wait loop written by hand."""
    found = []
    for loop in (n for n in ast.walk(ast.parse(source)) if isinstance(n, (ast.For, ast.While))):
        for node in ast.walk(loop):
            if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "sleep"
                    and isinstance(node.func.value, ast.Name) and node.func.value.id == "time"):
                argument = node.args[0] if node.args else None
                if not (isinstance(argument, ast.Constant) and isinstance(argument.value, (int, float)) and argument.value <= 0.5):
                    found.append(node.lineno)
    return sorted(set(found))


check("the rule finds a wait loop written by hand", sleeps_in_loops("import time\nfor _ in range(3):\n    if x():\n        break\n    time.sleep(2)\n") == [5])
check("and leaves a pause of half a second or less, between two steps, alone", sleeps_in_loops("import time\nfor _ in range(3):\n    time.sleep(0.5)\n") == [])
check("and a sleep that is not in a loop", sleeps_in_loops("import time\ntime.sleep(2)\n") == [])
by_hand = {os.path.basename(p): sleeps_in_loops(open(p).read()) for p in checks}
check("no check polls in a loop of its own: harness.wait_until does it, and catches an unanswered call", not any(by_hand.values()),
      {k: v for k, v in by_hand.items() if v})

print("=== every call of a harness helper from a check fits the helper's signature ===")
import inspect  # noqa: E402


def bad_calls(source):
    """(line, name, error) for each harness.<helper>(...) call whose arguments the helper cannot take (a keyword it has not got, one argument twice)."""
    found = []
    for node in ast.walk(ast.parse(source)):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name)
                and node.func.value.id == "harness" and callable(getattr(harness, node.func.attr, None))):
            target = getattr(harness, node.func.attr)
            if any(isinstance(a, ast.Starred) for a in node.args) or any(k.arg is None for k in node.keywords):
                continue
            try:
                inspect.signature(target).bind(*[None] * len(node.args), **{k.arg: None for k in node.keywords})
            except TypeError as e:
                found.append((node.lineno, node.func.attr, str(e)))
    return found


check("the rule finds a call with a keyword the helper has not got", bad_calls("harness.wait_until(p, 1, 2, speed=3)") != [])
check("and one argument given twice", bad_calls("harness.wait_until(p, 1, timeout=3)") != [])
check("and a call that fits is let through", bad_calls("harness.wait_until(p, 1, interval=3)") == [])
wrong = {os.path.basename(p): bad_calls(open(p).read()) for p in checks}
check("no check calls a helper with arguments it cannot take", not any(wrong.values()), {k: v for k, v in wrong.items() if v})

print()
if failed:
    print("test_harness: FAIL (%d)" % failed)
    sys.exit(1)
print("test_harness: PASS")
