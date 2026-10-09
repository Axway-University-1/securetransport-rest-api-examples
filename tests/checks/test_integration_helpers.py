#!/usr/bin/env python3
"""
Check the integration helpers that decide what a real-server run touches,
without a server.

31.subscriptions_routes_transfers_scripts.py runs the Admin examples as
name-substituted copies, so that they act on throwaway objects and never on
the account "john" or an application or route someone already has. If an
example is changed so that a substitution no longer applies, the copy would act
on the real name. This finds that here, before anyone runs --write.

Also checks release_at_least(), which decides whether the checks for
5.5-20260924 features run at all.

Runs offline. Exit code 0 means clean.
"""
import ast
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tests", "integration", "lib"))
import script_runner as runner  # noqa: E402
import st_client  # noqa: E402

failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1


print("=== release_at_least ===")
for version, release, want in (("5.5-20260924", "5.5-20260924", True),
                               ("5.5-20261231", "5.5-20260924", True),
                               ("5.5-20260923", "5.5-20260924", False),
                               ("5.6-20250101", "5.5-20260924", True),
                               ("5.4-20991231", "5.5-20260924", False),
                               ("5.5.1-20260101", "5.5-20260924", True),
                               ("5.5-mock", "5.5-20260924", False),
                               (None, "5.5-20260924", False)):
    check("%s is %s %s" % (version, "at least" if want else "older than", release),
          st_client.release_at_least(version, release) is want)

print()
print("=== a network error is an STError, which the checks handle ===")
# A server restarting its daemons can accept a connection and then not answer:
# urllib raises TimeoutError then, not URLError. Check 23's wait loop handles
# STError, so anything else escaped it and crashed the check.


class FailingOpener:
    def __init__(self, error):
        self.error = error

    def open(self, *args, **kwargs):
        raise self.error


for error in (TimeoutError("The read operation timed out"), ConnectionResetError("reset by peer")):
    for client in (st_client.STClient("st.example.com", "8444", "u", "p"),
                   st_client.EndUserClient("st.example.com", "8443", "u", "p")):
        client._opener = FailingOpener(error)
        try:
            client._request("GET", "daemons")
            raised = None
        except st_client.STError:
            raised = "STError"
        except Exception as e:  # noqa: BLE001 - what escapes is the point
            raised = type(e).__name__
        check("%s: %s becomes an STError" % (type(client).__name__, type(error).__name__),
              raised == "STError", raised)

print()
print("=== 31: every Admin example it runs is fully name-substituted ===")
CHECK_31 = os.path.join(REPO, "tests", "integration", "checks", "31.subscriptions_routes_transfers_scripts.py")
tree = ast.parse(open(CHECK_31).read())
scripts = next(ast.literal_eval(node.value) for node in ast.walk(tree)
               if isinstance(node, ast.Assign)
               and any(getattr(t, "id", None) == "ADMIN_SCRIPTS" for t in node.targets))

BASH = os.path.join(REPO, "Admin", "API 2.0", "bash")
subs = runner.chain_substitutions("ZZTEST_", "ssh.example.com", "2222")
# Real names that must not reach a line that runs, in any spelling
REAL = re.compile(r"\bjohn\b|(?<![A-Za-z0-9_])(AdvancedRoutingApplication|SimpleRoute|RouteFrom)")

for rel in scripts:
    path = os.path.join(BASH, rel)
    if not os.path.exists(path):
        check(rel + ": exists", False)
        continue
    text = runner.substitute(open(path).read(), subs)
    code = [line for line in text.splitlines() if not line.lstrip().startswith("#")]
    left = runner.unsubstituted(text, subs)
    real = [line.strip() for line in code if REAL.search(line)]
    check(rel + ": no real name is left in it", not left and not real, left or real[:3])

# With the defaults, st_server and port 8022, the host and port substitutions
# leave the text as it was. That is not a real name left behind.
defaults = runner.chain_substitutions("ZZTEST_", "${ST_SERVER}", "8022")
for rel in scripts:
    text = runner.substitute(open(os.path.join(BASH, rel)).read(), defaults)
    left = runner.unsubstituted(text, defaults)
    check(rel + ": with the default SSH host and port, nothing is left", not left, left)

pull = runner.substitute(open(os.path.join(BASH, "06.TransferSites/02.sites_POST_ssh.sh")).read(), subs)
check("the SSH sites point at the configured host and port",
      'PARTNER_HOST="ssh.example.com"' in pull and 'PARTNER_SSH_PORT="2222"' in pull)
check("a prefixed name is not mistaken for the real one",
      runner.unsubstituted("ZZTEST_SimpleRoute_Compress", subs) == []
      and runner.unsubstituted('X="SimpleRoute_Compress"', subs) == ["SimpleRoute_Compress"])

# Every example in the folders the newer examples added is run by 31 or 30
NEW = ("06.TransferSites", "07.Subscriptions", "09.CompositeRoutes", "15.Transfers", "16.TransferLogs")
OLDER = {"06.TransferSites/01.sites_POST.sh", "09.CompositeRoutes/02.routes_POST.sh"}  # 08 and 22 run these
BY_47 = {"16.TransferLogs/03.logs_transfers_id_GET.sh", "16.TransferLogs/04.logs_transfers_id_operations_POST.sh",
         "16.TransferLogs/05.logs_transfers_pullSummary_GET.sh"}  # 47.logs_scripts.py runs these
BY_50 = {"09.CompositeRoutes/08.routes_id_HEAD.sh", "09.CompositeRoutes/09.routes_id_PUT.sh",
         "09.CompositeRoutes/10.routes_id_PATCH.sh"}  # 50.routes_scripts.py runs these, on routes of its own
BY_54 = {"06.TransferSites/05.sites_id_HEAD.sh", "06.TransferSites/06.sites_id_GET.sh", "06.TransferSites/07.sites_id_PUT.sh",
         "06.TransferSites/08.sites_id_PATCH.sh", "06.TransferSites/09.sites_operations_POST_test.sh",
         "06.TransferSites/10.sites_operations_POST_test_new.sh",
         "06.TransferSites/11.sites_operations_POST_list.sh"}  # 54.sites_scripts.py runs these, on sites of its own
BY_56 = {"07.Subscriptions/05.subscriptions_id_HEAD.sh", "07.Subscriptions/06.subscriptions_id_GET.sh",
         "07.Subscriptions/07.subscriptions_id_PUT.sh", "07.Subscriptions/08.subscriptions_id_PATCH.sh",
         "07.Subscriptions/09.subscriptions_id_operations_POST_pull.sh",
         "07.Subscriptions/10.subscriptions_id_operations_POST_clearPullHistory.sh",
         "07.Subscriptions/11.subscriptions_id_operations_POST_purge.sh", "07.Subscriptions/12.subscriptions_POST_types.sh",
         "07.Subscriptions/13.subscriptions_id_DELETE_types.sh"}  # 56.subscriptions_scripts.py runs these, on subscriptions of its own
missing = sorted(os.path.join(folder, f) for folder in NEW for f in os.listdir(os.path.join(BASH, folder))
                 if f.endswith(".sh") and os.path.join(folder, f) not in set(scripts) | OLDER | BY_47 | BY_50 | BY_54 | BY_56)
check("every example in %s is run against a real server" % ", ".join(NEW), not missing, missing)
text_47 = open(os.path.join(REPO, "tests", "integration", "checks", "47.logs_scripts.py")).read()
check("and 47.logs_scripts.py names each one it is said to run", all(os.path.basename(f) in text_47 for f in BY_47),
      [f for f in BY_47 if os.path.basename(f) not in text_47])
text_54 = open(os.path.join(REPO, "tests", "integration", "checks", "54.sites_scripts.py")).read()
text_56 = open(os.path.join(REPO, "tests", "integration", "checks", "56.subscriptions_scripts.py")).read()
check("and 56.subscriptions_scripts.py names each one it is said to run", all(os.path.basename(f) in text_56 for f in BY_56),
      [f for f in BY_56 if os.path.basename(f) not in text_56])
check("and 54.sites_scripts.py names each one it is said to run", all(os.path.basename(f) in text_54 for f in BY_54),
      [f for f in BY_54 if os.path.basename(f) not in text_54])

print()
print("=== protocol_logins: a login that cannot be tried is an error, never an ok ===")
import shutil  # noqa: E402
import socket  # noqa: E402
import tempfile  # noqa: E402
import protocol_logins  # noqa: E402
closed = socket.socket()
closed.bind(("127.0.0.1", 0))
free_port = closed.getsockname()[1]
closed.close()
tried = protocol_logins.Logins("127.0.0.1", free_port, free_port, free_port, "x")
try:
    for proto in protocol_logins.PROTOCOLS:
        got = tried.try_login(proto, "nobody")
        check("%s to a closed port is not ok" % proto, got != "ok" and got.split(" ")[0] in ("error", "refused"), got)
    check("SFTP to a closed port is an error, never a refusal (a dead SSH daemon must not pass a 'refused' check)",
          tried.try_login("SFTP", "nobody").startswith("error"), tried.try_login("SFTP", "nobody"))
    for proto in ("HTTP", "FTP"):
        check("%s to a closed port is an error, not a refusal" % proto, tried.try_login(proto, "nobody").startswith("error"), tried.try_login(proto, "nobody"))
    quoted = protocol_logins.Logins("127.0.0.1", free_port, free_port, free_port, "x")
    try:
        import subprocess  # noqa: E402
        for pw in ("it's", 'a"b$c`d\\e', "plain"):
            printed = subprocess.run([quoted._askpass()], env=quoted._env(pw), capture_output=True, text=True).stdout
            check("the askpass script prints the password exactly: %r" % pw, printed == pw + "\n", printed)
    finally:
        quoted.cleanup()
    stubs = tempfile.mkdtemp(prefix="sftp_stub_")
    old_path = os.environ["PATH"]
    try:
        for message, want in (("Permission denied (publickey,password).", "refused"), ("ssh: connect to host x port 22: Connection refused", "error"),
                              ("Connection timed out", "error"), ("Could not resolve hostname x", "error")):
            with open(os.path.join(stubs, "sftp"), "w") as f:
                f.write("#!/bin/sh\ncat >/dev/null\necho '%s' >&2\nexit 255\n" % message)
            os.chmod(os.path.join(stubs, "sftp"), 0o755)
            os.environ["PATH"] = stubs + os.pathsep + old_path
            got = tried.try_login("SFTP", "nobody")
            check("sftp saying %r is %s" % (message[:30], want), got.startswith(want), got)
    finally:
        os.environ["PATH"] = old_path
        shutil.rmtree(stubs, ignore_errors=True)
    check("SFTP is core, FTP is the legacy one, listed last", protocol_logins.PROTOCOLS == ("SFTP", "HTTP", "FTP"))
    # The ports come from harness.ports() as text, because a config holds text
    as_text = protocol_logins.Logins("127.0.0.1", str(free_port), str(free_port), str(free_port), "x")
    try:
        for proto in protocol_logins.PROTOCOLS:
            got = as_text.try_login(proto, "nobody")
            check("%s with the ports as text is an error or a refusal, not an exception" % proto, got.split(" ")[0] in ("error", "refused"), got)
        try:
            as_text.open_login("FTP", "nobody")
            raised = "no error"
        except OSError:
            raised = "OSError"
        except Exception as e:  # noqa: BLE001
            raised = type(e).__name__
        check("an FTP login kept open to a closed port, the port as text, fails as a connection error", raised == "OSError", raised)
    finally:
        as_text.cleanup()
finally:
    tried.cleanup()

import time  # noqa: E402
print("=== an open SFTP login says it is dead when the server ended the session, not only when the client exited ===")
stubs = tempfile.mkdtemp(prefix="sftp_stub_")
old_path = os.environ["PATH"]
try:
    marker = os.path.join(stubs, "session_ended")
    # a stand-in sftp: it reads commands from standard input and, once the "server" has ended the session (the marker file),
    # exits when it is sent the next one - which is what the real client does, and why a client that nobody types to looks alive
    with open(os.path.join(stubs, "sftp"), "w") as f:
        f.write('#!/bin/sh\nwhile read line; do\n  if [ -e "%s" ]; then echo "Connection closed" >&2; exit 1; fi\ndone\n' % marker)
    os.chmod(os.path.join(stubs, "sftp"), 0o755)
    os.environ["PATH"] = stubs + os.pathsep + old_path
    kept = protocol_logins.Logins("127.0.0.1", 1, 1, 1, "x")
    try:
        holder = kept.open_login("SFTP", "someone")
        check("an open SFTP login is alive while the session is", holder.alive() is True)
        check("... and stays so when asked again", holder.alive() is True)
        open(marker, "w").close()
        started = time.time()
        gone = holder.alive()
        check("once the server has ended the session it is dead at the next look, though the client was never closed", gone is False, gone)
        check("... and it is quick to say so", time.time() - started < 5)
        check("a client that already exited is dead too", holder.alive() is False)
        holder.close()
    finally:
        kept.cleanup()
finally:
    os.environ["PATH"] = old_path
    shutil.rmtree(stubs, ignore_errors=True)

print("=== the harness never writes over your own configuration ===")
import shutil as _shutil  # noqa: E402
import subprocess as _subprocess  # noqa: E402
import tempfile as _tempfile  # noqa: E402

ADMIN_TREE = runner.path("Admin", "API 2.0", "bash")
EU_TREE = runner.path("EndUser", "API 2.0", "bash")
CFG = {"st_server": "h.example", "st_port": "444", "st_user": "adm", "st_password": "p$w\"x'y"}
EU_CFG = dict(CFG, st_port="8443", st_user="enduser", st_password="eupass")


def sees(tree, var):
    """What a script sees in var after it sources the tree's set_variables.sh."""
    out = _subprocess.run(["bash", "-c", 'source ./set_variables.sh >/dev/null 2>&1; printf "%s" "${!1}"', "_", var],
                          cwd=tree, capture_output=True, text=True)
    return out.stdout


def local_state(tree):
    f = os.path.join(tree, "set_variables.local.sh")
    return open(f).read() if os.path.exists(f) else None


before = (local_state(ADMIN_TREE), local_state(EU_TREE))
with runner.real_credentials(ADMIN_TREE, CFG):
    var_file = os.environ.get("ST_ADMIN_LOCAL_VARIABLES")
    check("the scripts read the credentials from a temporary file", bool(var_file) and os.path.exists(var_file), var_file)
    check("that file is readable by its owner only", (os.stat(var_file).st_mode & 0o777) == 0o600)
    check("a script sourcing set_variables.sh sees the server", sees(ADMIN_TREE, "ST_SERVER") == "h.example", sees(ADMIN_TREE, "ST_SERVER"))
    check("a password with $, a double and a single quote arrives as it was", sees(ADMIN_TREE, "ST_PASSWORD") == CFG["st_password"], sees(ADMIN_TREE, "ST_PASSWORD"))
    check("your own set_variables.local.sh is not touched while it runs", local_state(ADMIN_TREE) == before[0])
    with runner.real_credentials(EU_TREE, EU_CFG):
        check("the Admin and the EndUser tree each get their own credentials inside each other",
              (sees(ADMIN_TREE, "ST_USER"), sees(EU_TREE, "ST_USER")) == ("adm", "enduser"),
              (sees(ADMIN_TREE, "ST_USER"), sees(EU_TREE, "ST_USER")))
    check("leaving the inner one leaves the outer one in place", sees(ADMIN_TREE, "ST_USER") == "adm")
    with runner.real_credentials(ADMIN_TREE, dict(CFG, st_user="inner")):
        check("an inner context on the same tree wins", sees(ADMIN_TREE, "ST_USER") == "inner")
    check("and the outer one is back after it", sees(ADMIN_TREE, "ST_USER") == "adm")
check("the temporary file is gone afterwards", not os.path.exists(var_file))
check("the variable is gone afterwards", "ST_ADMIN_LOCAL_VARIABLES" not in os.environ and "ST_ENDUSER_LOCAL_VARIABLES" not in os.environ)
check("your own local files are exactly as they were", (local_state(ADMIN_TREE), local_state(EU_TREE)) == before)
try:
    with runner.real_credentials(ADMIN_TREE, CFG):
        var_file = os.environ["ST_ADMIN_LOCAL_VARIABLES"]
        raise RuntimeError("a check failed")
except RuntimeError:
    pass
check("an exception inside the block still cleans up", not os.path.exists(var_file) and "ST_ADMIN_LOCAL_VARIABLES" not in os.environ)

work = _tempfile.mkdtemp(prefix="harness_test_")
child = """
import os, signal, sys, time
sys.path.insert(0, sys.argv[1])
import script_runner as r
with r.real_credentials(sys.argv[2], {"st_server": "h", "st_port": "1", "st_user": "u", "st_password": "p"}):
    print(os.environ["ST_ADMIN_LOCAL_VARIABLES"], flush=True)
    os.kill(os.getpid(), signal.SIGTERM)
    time.sleep(5)
"""
killed = _subprocess.run([sys.executable, "-c", child, os.path.join(REPO, "tests", "integration", "lib"), ADMIN_TREE],
                         capture_output=True, text=True, timeout=30)
check("a process killed with SIGTERM leaves no credentials file behind",
      killed.returncode == 143 and killed.stdout.strip() != "" and not os.path.exists(killed.stdout.strip()),
      (killed.returncode, killed.stdout, killed.stderr[-200:]))

saved = (runner.BACKUP_DIR, runner._NOTE, runner._ORIG, runner._ABSENT)
backups = os.path.join(work, "backups")
runner.BACKUP_DIR, runner._NOTE, runner._ORIG, runner._ABSENT = (
    backups, backups + "/python_config.target", backups + "/python_config.orig", backups + "/python_config.absent")
tree = os.path.join(work, "py")
os.makedirs(tree)
config_file = os.path.join(tree, "config")


def leftovers():
    return sorted(os.listdir(backups)) if os.path.isdir(backups) else []


try:
    open(config_file, "w").write("mine\n")
    with runner.real_credentials_python(tree, CFG):
        check("the python config is written for the run", 'st_user="adm"' in open(config_file).read())
        check("your own one is kept on disk meanwhile", open(runner._ORIG).read() == "mine\n")
    check("your own python config is back, byte for byte", open(config_file).read() == "mine\n")
    check("and no backup is left", leftovers() == [], leftovers())

    os.remove(config_file)
    with runner.real_credentials_python(tree, CFG):
        pass
    check("with no python config before, there is none after", not os.path.exists(config_file) and leftovers() == [])

    open(config_file, "w").write("mine\n")
    try:
        with runner.real_credentials_python(tree, CFG):
            raise RuntimeError("a check failed")
    except RuntimeError:
        pass
    check("an exception inside the block puts it back too", open(config_file).read() == "mine\n")

    with runner.real_credentials_python(tree, CFG):
        with runner.real_credentials_python(tree, dict(CFG, st_user="inner")):
            check("an inner python context wins", 'st_user="inner"' in open(config_file).read())
        check("and the outer one is back after it", 'st_user="adm"' in open(config_file).read())
    check("nesting still ends with your own config", open(config_file).read() == "mine\n" and leftovers() == [])

    child_py = """
import os, signal, sys, time
sys.path.insert(0, sys.argv[1])
import script_runner as r
b = sys.argv[3]
r.BACKUP_DIR, r._NOTE, r._ORIG, r._ABSENT = b, b + "/python_config.target", b + "/python_config.orig", b + "/python_config.absent"
with r.real_credentials_python(sys.argv[2], {"st_server": "h", "st_port": "1", "st_user": "u", "st_password": "p"}):
    os.kill(os.getpid(), getattr(signal, sys.argv[4]))
    time.sleep(5)
"""
    lib = os.path.join(REPO, "tests", "integration", "lib")

    def run_child(sig):
        return _subprocess.run([sys.executable, "-c", child_py, lib, tree, backups, sig], capture_output=True, text=True, timeout=30)

    killed = run_child("SIGTERM")
    check("a process killed with SIGTERM puts the python config back",
          killed.returncode == 143 and open(config_file).read() == "mine\n" and leftovers() == [],
          (killed.returncode, killed.stderr[-200:]))

    # SIGKILL cannot be caught: nothing runs, so the harness copy and the backup stay
    killed = run_child("SIGKILL")
    check("a process killed with SIGKILL leaves the harness copy, and your config safe in a backup",
          killed.returncode == -9 and 'st_user="u"' in open(config_file).read() and open(runner._ORIG).read() == "mine\n",
          (killed.returncode, leftovers()))
    with runner.real_credentials_python(tree, dict(CFG, st_user="second")):
        check("the next run keeps your config, not the killed run's copy", open(runner._ORIG).read() == "mine\n")
    check("and ends with your own config again", open(config_file).read() == "mine\n" and leftovers() == [])
finally:
    runner.BACKUP_DIR, runner._NOTE, runner._ORIG, runner._ABSENT = saved
    runner._python_depth = 0
    _shutil.rmtree(work, ignore_errors=True)

check("the python backups live under tests/local, which git ignores",
      os.path.relpath(runner.BACKUP_DIR, REPO).startswith(os.path.join("tests", "local")))

print("=== the mock run does not move your integration.conf ===")
old = os.environ.pop("ST_INTEGRATION_CONF", None)
try:
    check("config_path is tests/local/integration.conf by default",
          st_client.config_path() == os.path.join(REPO, "tests", "local", "integration.conf"), st_client.config_path())
    os.environ["ST_INTEGRATION_CONF"] = "/tmp/some_other.conf"
    check("ST_INTEGRATION_CONF names another one", st_client.config_path() == "/tmp/some_other.conf")
finally:
    os.environ.pop("ST_INTEGRATION_CONF", None)
    if old is not None:
        os.environ["ST_INTEGRATION_CONF"] = old
runner_text = open(os.path.join(REPO, "tests", "integration", "run_integration.sh")).read()
check("run_integration.sh --mock uses its own temporary config instead of moving yours",
      "ST_INTEGRATION_CONF" in runner_text and 'mv "${CONF}"' not in runner_text and "realbackup" not in runner_text)


print("=== a check that asserts nothing is a skip, not a pass ===")
import contextlib as _contextlib  # noqa: E402
import io as _io  # noqa: E402

buffer = _io.StringIO()
with _contextlib.redirect_stdout(buffer):
    empty = st_client.Checker("nothing asserted")
    empty.done()
check("Checker.done() with no assertion says SKIP", "SKIP  no assertion was made" in buffer.getvalue(), buffer.getvalue())
buffer = _io.StringIO()
with _contextlib.redirect_stdout(buffer):
    one = st_client.Checker("one assertion")
    one.check("it holds", True)
    one.done()
check("and with an assertion it does not", "SKIP" not in buffer.getvalue(), buffer.getvalue())

work = _tempfile.mkdtemp(prefix="runner_test_")
try:
    integration = os.path.join(work, "integration")
    os.makedirs(os.path.join(integration, "checks"))
    _shutil.copy(os.path.join(REPO, "tests", "integration", "run_integration.sh"), integration)
    os.makedirs(os.path.join(integration, "lib"))
    _shutil.copy(os.path.join(REPO, "tests", "integration", "lib", "run_check.py"), os.path.join(integration, "lib"))
    fake = {"01.ok.py": 'print("  3 passed, 0 failed")',
            "02.zero.py": 'print("  0 passed, 0 failed")',
            "03.skip.py": 'print("  SKIP  no server")',
            "04.fail.py": 'import sys\nprint("  1 passed, 1 failed")\nprint("  SKIP  a note")\nsys.exit(1)',
            "100.ok.py": 'print("  1 passed, 0 failed")'}
    for name, code in fake.items():
        with open(os.path.join(integration, "checks", name), "w") as f:
            f.write(code + "\n")
    conf = os.path.join(work, "integration.conf")
    with open(conf, "w") as f:
        f.write('st_server="127.0.0.1"\nst_port="1"\nst_user="u"\nst_password="p"\nst_confirm_lab="yes"\n')
    env = dict(os.environ, ST_INTEGRATION_CONF=conf)

    def run_runner(*args):
        return _subprocess.run(["bash", os.path.join(integration, "run_integration.sh")] + list(args),
                               capture_output=True, text=True, env=env, timeout=60)

    result = run_runner()
    order = re.findall(r"\((\d+\.\w+\.py): \d+ s\)", result.stdout)
    check("the checks run in number order, 100 after 04", order == ["01.ok.py", "02.zero.py", "03.skip.py", "04.fail.py", "100.ok.py"], order)
    check("a pass, a zero-assertion check, a skip, a failure and a pass count as 2 passed, 2 skipped, 1 failed",
          "1 INTEGRATION CHECK(S) FAILED, 2 passed, 2 skipped" in result.stdout, result.stdout[-300:])
    check("a failure counts even when it also printed a SKIP line, and the exit status is 1",
          result.returncode == 1 and "04.fail.py" in result.stdout.split("INTEGRATION CHECK(S) FAILED")[-1])
    result = run_runner("ok")
    check("a word on the command line runs only the checks with it in their name",
          re.findall(r"\((\d+\.\w+\.py): ", result.stdout) == ["01.ok.py", "100.ok.py"] and "INTEGRATION PASSED  (2 check(s), 0 skipped" in result.stdout,
          result.stdout[-200:])
    result = run_runner("--no-such-option")
    check("an unknown option is refused", result.returncode == 2, result.returncode)
    result = run_runner("-h")
    check("-h prints the header of the runner, from any folder", result.returncode == 0 and "Run the integration checks" in result.stdout
          and "ST_CHECK_TIMEOUT" in result.stdout, (result.returncode, result.stdout[-200:], result.stderr[-200:]))
finally:
    _shutil.rmtree(work, ignore_errors=True)

print("=== --write reaches a check only when the config allows writing, and a check that hangs is stopped ===")
import time as _time  # noqa: E402
work = _tempfile.mkdtemp(prefix="runner_test_")
try:
    integration = os.path.join(work, "integration")
    os.makedirs(os.path.join(integration, "checks"))
    os.makedirs(os.path.join(integration, "lib"))
    _shutil.copy(os.path.join(REPO, "tests", "integration", "run_integration.sh"), integration)
    _shutil.copy(os.path.join(REPO, "tests", "integration", "lib", "run_check.py"), os.path.join(integration, "lib"))
    fake = {
        "01.argv.py": 'import sys\nprint("ARGV " + " ".join(sys.argv[1:]))\nprint("  1 passed, 0 failed")',
        "02.hang.py": 'import signal, sys, time\n'
                      'def term(signum, frame):\n    print("  ..    cleanup ran after SIGTERM", flush=True)\n    sys.exit(143)\n'
                      'signal.signal(signal.SIGTERM, term)\nprint("  ..    started", flush=True)\ntime.sleep(120)',
        "03.deaf.py": 'import signal, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nprint("  ..    deaf", flush=True)\ntime.sleep(120)',
        "04.quick.py": 'print("  2 passed, 0 failed")',
    }
    for name, code in fake.items():
        with open(os.path.join(integration, "checks", name), "w") as f:
            f.write(code + "\n")

    def conf_with(allow):
        path = os.path.join(work, "integration_%s.conf" % (allow or "unset"))
        with open(path, "w") as f:
            f.write('st_server="127.0.0.1"\nst_port="1"\nst_user="u"\nst_password="p"\nst_confirm_lab="yes"\n'
                    + ('st_allow_writes="%s"\n' % allow if allow else ""))
        return path

    def run_with(conf, *args, **more_env):
        env = dict(os.environ, ST_INTEGRATION_CONF=conf, **more_env)
        return _subprocess.run(["bash", os.path.join(integration, "run_integration.sh")] + list(args),
                               capture_output=True, text=True, env=env, timeout=120)
    for allow, want_write in ((None, False), ("no", False), ("yes", True), ("YES", True), ("true", True)):
        result = run_with(conf_with(allow), "--write", "argv")
        got = re.search(r"^ARGV(.*)$", result.stdout, re.M)
        check("--write with st_allow_writes %s: the check %s it" % (allow or "not in the config", "gets" if want_write else "does not get"),
              got is not None and ("--write" in got.group(1)) is want_write, result.stdout[-300:])
        check("... and the banner says so: %s" % ("read and write" if want_write else "read only, because st_allow_writes is not yes"),
              (("READ AND WRITE" in result.stdout) if want_write else ("read only, because st_allow_writes is not yes" in result.stdout)), result.stdout[:400])
    result = run_with(conf_with("yes"), "argv")
    check("without --write on the command line the check does not get it either, whatever the config says",
          "ARGV" in result.stdout and "--write" not in re.search(r"^ARGV(.*)$", result.stdout, re.M).group(1) and "mode   : read only" in result.stdout)

    started = _time.time()
    result = run_with(conf_with("yes"), "hang", ST_CHECK_TIMEOUT="2", ST_CHECK_GRACE="10")
    took = _time.time() - started
    check("a check that hangs is stopped after ST_CHECK_TIMEOUT seconds, not left to hang the run", took < 30, took)
    check("it counts as FAILED, with a clear message that names the check and the limit",
          result.returncode == 1 and "1 INTEGRATION CHECK(S) FAILED" in result.stdout and "02.hang.py" in result.stdout.split("INTEGRATION CHECK(S) FAILED")[-1]
          and "02.hang.py did not finish within 2 seconds (ST_CHECK_TIMEOUT)" in result.stdout, result.stdout[-500:])
    check("it was asked to stop with SIGTERM first, so that its cleanup runs", "cleanup ran after SIGTERM" in result.stdout, result.stdout[-500:])
    started = _time.time()
    result = run_with(conf_with("yes"), "deaf", ST_CHECK_TIMEOUT="1", ST_CHECK_GRACE="2")
    check("a check that ignores SIGTERM is killed when its grace period is over, and says so",
          "was killed (SIGKILL)" in result.stdout and result.returncode == 1 and _time.time() - started < 30, result.stdout[-400:])
    result = run_with(conf_with("yes"), "quick", ST_CHECK_TIMEOUT="30")
    check("a check that finishes in time is not touched by the limit", result.returncode == 0 and "did not finish" not in result.stdout, result.stdout[-300:])
    result = run_with(conf_with("yes"), "quick")
    check("with no ST_CHECK_TIMEOUT there is a limit (1800 seconds) and a quick check still passes", result.returncode == 0, result.stdout[-300:])
finally:
    _shutil.rmtree(work, ignore_errors=True)

sys.path.insert(0, os.path.join(REPO, "tests", "integration", "lib"))
import run_check  # noqa: E402
for value, want in (("", 1800.0), ("600", 600.0), ("0", None), ("none", None), ("-5", None), ("abc", 1800.0), (" 45 ", 45.0)):
    os.environ["ST_CHECK_TIMEOUT"] = value
    got = run_check.seconds("ST_CHECK_TIMEOUT", run_check.DEFAULT_TIMEOUT)
    check("ST_CHECK_TIMEOUT=%r means %r" % (value, want), got == want, got)
os.environ.pop("ST_CHECK_TIMEOUT", None)
check("the default limit is half an hour and the grace period two minutes", run_check.DEFAULT_TIMEOUT == 1800 and run_check.DEFAULT_GRACE == 120)

# A Ctrl-C reaches the wrapper, not the check, which is in a group of its own: the wrapper has to pass it on
import signal as _signal  # noqa: E402
import subprocess as _sp  # noqa: E402
import tempfile as _tf  # noqa: E402
with _tf.TemporaryDirectory() as _work:
    child = os.path.join(_work, "child.py")
    with open(child, "w") as f:
        f.write('import signal, sys, time\n'
                'def handle(signum, frame):\n    print("child got signal %d" % signum, flush=True)\n    sys.exit(130)\n'
                'signal.signal(signal.SIGINT, handle)\nprint("child started", flush=True)\ntime.sleep(60)\n')
    wrapper = _sp.Popen([sys.executable, os.path.join(REPO, "tests", "integration", "lib", "run_check.py"), child], stdout=_sp.PIPE, text=True)
    first = wrapper.stdout.readline()
    wrapper.send_signal(_signal.SIGINT)
    rest = wrapper.communicate(timeout=30)[0]
    check("a SIGINT sent to the wrapper reaches the check it runs, and the check's own exit status comes back",
          "child started" in first and "child got signal 2" in rest and wrapper.returncode == 130, (first, rest, wrapper.returncode))

print("=== the mock leaves nothing behind ===")
import glob as _glob  # noqa: E402
import socket as _socket  # noqa: E402
import time as _time  # noqa: E402

# Its own temp folder (TMPDIR), so that another mock running at the same moment, on a
# developer's machine or in a parallel run, cannot be mistaken for a leftover of this one
tmp_root = _tempfile.mkdtemp(prefix="mock_tmp_")
probe = _socket.socket()
probe.bind(("127.0.0.1", 0))
mock_port = probe.getsockname()[1]
probe.close()
mock = _subprocess.Popen([sys.executable, os.path.join(REPO, "tests", "integration", "mock", "mock_st.py"), "--port", str(mock_port)],
                         stdout=_subprocess.DEVNULL, stderr=_subprocess.DEVNULL, env=dict(os.environ, TMPDIR=tmp_root))
try:
    up = False
    for _ in range(100):
        try:
            _socket.create_connection(("127.0.0.1", mock_port), timeout=0.2).close()
            up = True
            break
        except OSError:
            _time.sleep(0.1)
    check("the mock starts", up)
    # It listens as soon as the port is bound, a moment before it has loaded its certificate and
    # removed the folder: give it a few seconds to get there
    for _ in range(100):
        if not _glob.glob(os.path.join(tmp_root, "mock_st_*")):
            break
        _time.sleep(0.1)
    check("and no mock_st_* folder (its key) is left in its temp folder while it runs",
          _glob.glob(os.path.join(tmp_root, "mock_st_*")) == [], _glob.glob(os.path.join(tmp_root, "mock_st_*")))
finally:
    mock.terminate()
    mock.wait(timeout=10)
    _shutil.rmtree(tmp_root, ignore_errors=True)
check(".gitignore covers the name substituted copies a killed check leaves", ".zztest_*" in open(os.path.join(REPO, ".gitignore")).read())

print("=== a check that compares days waits out midnight ===")
import datetime as _datetime  # noqa: E402
D = _datetime.datetime
wait = st_client.seconds_to_wait_for_midnight
check("at noon it does not wait", wait(D(2026, 10, 8, 12, 0, 0)) == 0)
check("two minutes before midnight it does not wait", wait(D(2026, 10, 8, 23, 58, 0)) == 0)
check("a minute before midnight it waits for it, and a few seconds more", wait(D(2026, 10, 8, 23, 59, 0)) == 65, wait(D(2026, 10, 8, 23, 59, 0)))
check("a second before midnight it waits 6 seconds", wait(D(2026, 10, 8, 23, 59, 59)) == 6, wait(D(2026, 10, 8, 23, 59, 59)))
check("just after midnight it does not wait", wait(D(2026, 10, 9, 0, 0, 3)) == 0)
check("the last day of a month and of a year are no different",
      wait(D(2026, 12, 31, 23, 59, 30)) == 35 and wait(D(2026, 2, 28, 23, 59, 30)) == 35)
check("the two checks that compare days call it",
      all("avoid_midnight" in open(os.path.join(REPO, "tests", "integration", "checks", f)).read()
          for f in ("30.lookups_and_transfer_logs_read.py", "55.statistics_summary_scripts.py")))
print()
if failed:
    print("test_integration_helpers: FAIL (%d)" % failed)
    sys.exit(1)
print("test_integration_helpers: PASS")
