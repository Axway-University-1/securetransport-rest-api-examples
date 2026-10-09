#!/usr/bin/env python3
"""
What the integration checks have in common, in one place.

A check used to carry its own copy of each of these (a gate for --write, the ports
of the servers, a function that runs an example and checks its exit code, a wait
loop, an account to log in as). The copies had drifted apart: one wait loop did
not catch a refused connection, another did, and a fix made in one never reached
the others. Each is here once, and tests/checks/test_harness.py proves it offline.

  require_writes(config, what)   the gate: skip (exit 0) unless a config exists, --write is
                                 on the command line and the config says st_allow_writes
  connect(config, c, mock=...)   log in; when the server is the bundled mock and `mock` says
                                 why the check cannot run on it, say so and end the check
  ports(config, admin)           the EndUser, SSH, FTP and PeSIT ports: the config's, else the
                                 ones the Admin API lists for the running servers, else the default
  servers_list(admin)            GET /servers as a list, whichever way the answer is wrapped
  run_script(c, folder, name, args, expect_rc, timeout, env, ...)
                                 run a shipped example, check its exit code, return its output;
                                 bind_script(...) makes the `script(name, args)` of a check
  wait_until(predicate, timeout, interval)
                                 poll until the predicate holds; a refused or unanswered call
                                 (st_client.STError) is one more "not yet"; returns the last value
  settled(read, condition, ...)  poll a read until its value satisfies the condition; returns the value
  throwaway_account(admin, c, config, ...)
                                 a user account with a fresh name and user id, whose files and
                                 then which itself are deleted when the block ends
  scratch(prefix)                a temporary folder that is removed when the check ends, however it ends
  new_password(), suffix(n)      random text for a password and for a name

This module needs only the standard library, like st_client.
"""
import atexit
import base64
import contextlib
import os
import random
import shutil
import string
import sys
import tempfile
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

YES = ("yes", "true", "1")

# Where each server listens when neither the config nor the Admin API says: the ports of a stock install
DEFAULT_SSH_PORT = "8022"
DEFAULT_PESIT_PORT = "17617"


# --------------------------------------------------------------------------
# The gate
# --------------------------------------------------------------------------
def writes_allowed(config, argv=None):
    """True when the config exists, --write is on the command line and the config says st_allow_writes."""
    argv = sys.argv if argv is None else argv
    return bool(config) and "--write" in argv and str(config.get("st_allow_writes", "no")).lower() in YES


def require_writes(config, what="run the examples for real", argv=None):
    """
    The gate every check that writes starts with. Skips (exit 0, nothing was asked of the server) when
    there is no config, when --write was not given, or when st_allow_writes is not yes in the config.
    `what` completes "read only run, pass --write to ...". Returns the config.
    """
    argv = sys.argv if argv is None else argv
    if not config:
        st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
    if "--write" not in argv:
        st_client.skip("read only run, pass --write to " + what)
    if str(config.get("st_allow_writes", "no")).lower() not in YES:
        st_client.skip('st_allow_writes is not "yes" in integration.conf')
    return config


def connect(config, c, mock=None):
    """
    st_client.connect() and, when `mock` is given and the server is the bundled mock, the bail-out every
    check had: say why this check cannot run on the mock (`mock`), log out and end the check with
    its verdict (a check that asserted nothing is a skip). Returns the logged in client.
    """
    client = st_client.connect(config, c)
    if mock and st_client.is_mock(client):
        c.info(mock)
        client.logout()
        sys.exit(c.done())
    return client


# --------------------------------------------------------------------------
# Ports
# --------------------------------------------------------------------------
def servers_list(admin):
    """GET /servers as a list of servers: the answer is a plain array on some releases and {"result": [...]} on others."""
    response = admin.get("servers")
    body = response.json() if response.status == 200 else None
    if isinstance(body, dict):
        body = body.get("result", [])
    return body if isinstance(body, list) else []


# The field that holds the port of each protocol's server in GET /servers
_PORT_FIELD = {"ssh": "port", "ftp": "port", "pesit": "pesitPort"}


def discovered_ports(servers):
    """
    {protocol: port} of the servers GET /servers lists, for ssh, ftp and pesit. A server that is running wins over
    one that is stopped (the lab has stopped test servers listed after the default one); the first of its kind
    otherwise. A protocol with no server that has a port is not in the answer.
    """
    found = {}
    for protocol, field in _PORT_FIELD.items():
        candidates = [s for s in servers if s.get("protocol") == protocol and s.get(field)]
        candidates.sort(key=lambda s: not s.get("isActive"))   # stable: a running one first, otherwise the list's own order
        if candidates:
            found[protocol] = str(candidates[0][field])
    return found


class Ports:
    """The ports a check reaches the server on, as text: enduser, ssh, ftp (None when no FTP server is listed) and pesit."""

    def __init__(self, enduser, ssh, ftp, pesit):
        self.enduser, self.ssh, self.ftp, self.pesit = enduser, ssh, ftp, pesit

    def __repr__(self):
        return "Ports(enduser=%r, ssh=%r, ftp=%r, pesit=%r)" % (self.enduser, self.ssh, self.ftp, self.pesit)


def ports(config, admin=None):
    """
    The ports of the EndUser API, SSH, FTP and PeSIT servers. From the config when it names one
    (st_enduser_port, st_ssh_port, st_pesit_port; blank counts as not named); else, for SSH, FTP and PeSIT, from the
    servers the Admin API lists (when `admin` is given); else the default: the admin port minus one for the EndUser API
    (not always right: set st_enduser_port), 8022 for SSH, 17617 for PeSIT, and no FTP port at all.
    """
    found = discovered_ports(servers_list(admin)) if admin is not None else {}
    return Ports(
        enduser=config.get("st_enduser_port") or str(int(config["st_port"]) - 1),
        ssh=config.get("st_ssh_port") or found.get("ssh") or DEFAULT_SSH_PORT,
        ftp=found.get("ftp"),
        pesit=config.get("st_pesit_port") or found.get("pesit") or DEFAULT_PESIT_PORT)


# --------------------------------------------------------------------------
# Running an example
# --------------------------------------------------------------------------
class Output(str):
    """What an example printed (stdout and stderr), as text; `returncode` is its exit code."""
    returncode = None


def _rc_text(expect_rc):
    wanted = expect_rc if isinstance(expect_rc, (tuple, list, set, frozenset)) else (expect_rc,)
    return wanted, " or ".join(str(w) for w in wanted)


def run_script(c, folder, name, args=None, expect_rc=0, timeout=60, env=None, tail=300, label=None,
               retry_text=None, retries=5, retry_delay=2, arg_width=None, hide=()):
    """
    Run the shipped example `folder`/`name` (from its own folder, as a person would), check its exit code with `c`
    and return its output (stdout and stderr; an Output, a str that also has .returncode). `expect_rc` is one exit code or several that are all right; None
    asks for no check. `env` adds variables for this run only. The check is named
    "<name> <args> exits <rc>" (label="..." with {name}, {args} and {rc} changes it, or a function of the three; arg_width cuts each argument to
    that many characters in the name; an argument listed in `hide`, a password, is left out of it).

    retry_text: some lookups of the Admin API are not complete the first time ("Found 0 sites named ..."
    for a site that exists): when the output holds this text the example is run again, up to `retries` times,
    `retry_delay` seconds apart. Pass None to run it once.
    """
    for attempt in range(retries if retry_text else 1):
        result = runner.run(os.path.join(folder, name), args, timeout=timeout, env=env)
        out = result.stdout + result.stderr
        if retry_text and retry_text in out and attempt + 1 < retries:
            time.sleep(retry_delay)
            continue
        break
    if expect_rc is not None:
        wanted, rc_text = _rc_text(expect_rc)
        shown = " ".join((a[:arg_width] if arg_width else a) for a in (args or []) if a not in hide)
        text = label(name, shown, rc_text) if callable(label) else (label or "{name} {args} exits {rc}").format(name=name, args=shown, rc=rc_text)
        c.check(text, result.returncode in wanted, out.strip()[-tail:])
    out = Output(out)
    out.returncode = result.returncode
    return out


def bind_script(c, folder, timeout=60, tail=300, label=None, retry_text=None, arg_width=None, hide=()):
    """
    The `script(name, args=None, expect_rc=0, env=None, retry=True)` of a check: run_script() with this checker, this
    folder and these settings fixed. `retry=False` runs it once whatever retry_text was bound.
    """
    def script(name, args=None, expect_rc=0, env=None, retry=True):
        return run_script(c, folder, name, args, expect_rc, timeout=timeout, env=env, tail=tail, label=label,
                          retry_text=retry_text if retry else None, arg_width=arg_width, hide=hide)
    return script


# --------------------------------------------------------------------------
# Waiting
# --------------------------------------------------------------------------
def wait_until(predicate, timeout=30, interval=1):
    """
    Poll `predicate` until it returns something true or `timeout` seconds have passed, `interval` apart, and give back
    the last value it returned (so the caller can show it). It is asked once more at the deadline, so an answer that
    arrives just then still counts.

    A call to the server that is refused or not answered (st_client.STError) is not a crash but "not yet": a
    server restarting its daemons does that (check 23 documents it). The value of such an attempt is None.
    Nothing but STError is caught.
    """
    deadline = time.time() + timeout
    value = None
    while True:
        try:
            value = predicate()
        except st_client.STError:
            value = None
        if value or time.time() >= deadline:
            return value
        time.sleep(max(0, min(interval, deadline - time.time())))


def settled(read, condition, timeout=20, interval=1):
    """
    Poll read() until condition(value) holds (or `timeout`) and return the last value read, or None when it
    could not be read at all. For an object that the server takes a moment to show as it was changed.
    """
    last = [None]

    def look():
        last[0] = read()
        return last[0] is not None and condition(last[0])
    wait_until(look, timeout, interval)
    return last[0]


# --------------------------------------------------------------------------
# A temporary folder
# --------------------------------------------------------------------------
def scratch(prefix="st_check_"):
    """
    A new temporary folder (its path), removed with everything in it when this process ends: normally, with
    sys.exit() (which is how a check ends), on an exception, and on a SIGTERM (script_runner turns it into an exit,
    which is what the runner's timeout sends). Only a SIGKILL leaves it behind. A check used to call
    tempfile.mkdtemp() and forget the folder, and every run left one more in the system's temp folder.
    """
    path = tempfile.mkdtemp(prefix=prefix)
    atexit.register(shutil.rmtree, path, True)
    return path


# --------------------------------------------------------------------------
# Random text
# --------------------------------------------------------------------------
def new_password():
    """A password that meets the server's rules, different every time."""
    return "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"


def suffix(length=6):
    """Lowercase letters and digits, for a name that must not collide with another run's."""
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(length))


_used_uids = set()


def fresh_uid(low=50000, high=59999):
    """A user id this process has not used yet. A home folder keeps the id of the first account that made it (see st-api-gotchas)."""
    while True:
        uid = random.randint(low, high)
        if uid not in _used_uids:
            _used_uids.add(uid)
            return uid


# --------------------------------------------------------------------------
# A throwaway account
# --------------------------------------------------------------------------
class Account:
    """A user account made for one check: name, uid, password, home, whether it was created, and the server's answer."""

    def __init__(self, name, uid, password, home, created, response):
        self.name, self.uid, self.password, self.home = name, uid, password, home
        self.created, self.response = created, response
        self.notes = []

    def __repr__(self):
        return "Account(%r, uid=%r)" % (self.name, self.uid)


def empty_home(client, limit=500):
    """
    Delete every file under the home folder of the account `client` is logged in as (an EndUserClient), then its
    folders from the bottom up. Returns how many entries it removed. An account's home folder is not removed with the
    account and keeps what is in it, on the lab's disk.
    """
    removed = 0
    folders = []

    def walk(folder, depth):
        nonlocal removed
        if depth > 6 or removed >= limit:
            return
        response = client._request("GET", "files/" + urllib.parse.quote(folder.strip("/"))) if folder.strip("/") else client.list_files()
        if response.status != 200:
            return
        for entry in (response.json() or {}).get("files", []):
            name = entry.get("fileName")
            if not name:
                continue
            path = (folder.strip("/") + "/" + name).strip("/")
            if entry.get("isDirectory"):
                folders.append(path)
                walk(path, depth + 1)
            elif client.delete_file(urllib.parse.quote(path)).status in (200, 204):
                removed += 1
    walk("", 0)
    for path in sorted(folders, key=len, reverse=True):
        if client.delete_file(urllib.parse.quote(path)).status in (200, 204):
            removed += 1
    return removed


@contextlib.contextmanager
def throwaway_account(admin, c, config, name=None, prefix="example_acct", password=None, home=None, extra=None,
                      label=None, port_set=None, enduser_factory=None):
    """
    A user account for a check to log in as, made through the Admin API and removed when the block ends, whatever
    happened inside it. It has a name nobody has used (the prefix and random letters; or `name`, which the check
    made up the same way) and a user id this process has not used: a home folder outlives its account and keeps the
    uid of its first owner, and an account created later under the same name with another uid cannot make a folder
    in it (st-api-gotchas, "A home folder outlives its account and keeps its owner").

    On the way out it logs in over the EndUser API as the account and deletes what is in the home folder (the
    folder itself stays on the lab's disk; nothing can remove it), then deletes the account. A login that does not
    work is no reason to leave the account behind. Anything it could not do is in Account.notes, never an
    exception.

    `home` is the home folder path (default /home/<name>), `extra` more fields of the account (a business unit),
    `label` the text of the set up check (default "set up: the account <name>"). When the account cannot be
    created, the check fails with the server's answer and the check ends (the block is not entered).
    """
    name = name or "%s_%s" % (prefix, suffix())
    password = password or new_password()
    uid = fresh_uid()
    home = home or "/home/" + name
    body = {"name": name, "type": "user", "uid": str(uid), "gid": str(uid), "homeFolder": home,
            "user": {"name": name, "passwordCredentials": {"password": password}}}
    body.update(extra or {})
    response = admin.post("accounts", body)
    created = response.status == 201
    c.check(label or "set up: the account " + name, created, response.text[:200])
    account = Account(name, uid, password, home, created, response)
    try:
        if not created:
            raise SystemExit(c.done())
        yield account
    finally:
        found = port_set or ports(config)
        factory = enduser_factory or st_client.EndUserClient
        if created:
            try:
                client = factory(config["st_server"], found.enduser, name, password)
                if client.login_response().status == 200:
                    try:
                        account.notes.append("%d entries removed from the home folder" % empty_home(client))
                    finally:
                        client.logout()
                else:
                    account.notes.append("could not log in to remove the files")
            except Exception as e:  # noqa: BLE001 - a clean-up never raises: the account must still be deleted below
                account.notes.append("could not remove the files: %s" % e)
            try:
                gone = admin.delete("accounts/" + name)
                if gone.status not in (200, 204, 404):
                    account.notes.append("delete answered %s: %s" % (gone.status, gone.text[:100]))
                    c.info("the account %s was NOT removed (HTTP %s): remove it by hand" % (name, gone.status))
            except st_client.STError as e:
                account.notes.append("delete failed: %s" % e)
                c.info("the account %s was NOT removed (%s): remove it by hand" % (name, e))
