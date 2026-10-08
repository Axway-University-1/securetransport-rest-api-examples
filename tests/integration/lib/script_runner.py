#!/usr/bin/env python3
"""
Run the actual, unmodified example scripts against a configured server.

st_client.py talks to the API the way the harness thinks the examples do.
This module runs the real files instead, exactly as a person would: from the
script's own directory, picking up credentials from set_variables.local.sh.
A bug in the curl invocation itself - bad quoting, a stale field name, a
broken jq filter - is what this catches that a reimplemented client cannot.
"""
import contextlib
import os
import re
import shlex
import shutil
import signal
import subprocess
import tempfile

REPO_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


def path(*parts):
    """A path under the repository root, e.g. path('Admin', 'API 2.0', 'bash')."""
    return os.path.join(REPO_ROOT, *parts)


def _on_sigterm(signum, frame):
    # Turn a kill into an exit that runs the finally blocks below, so a temporary
    # file is removed and the python config is put back.
    raise SystemExit(128 + signum)


try:
    signal.signal(signal.SIGTERM, _on_sigterm)
except ValueError:  # imported from a thread other than the main one
    pass


@contextlib.contextmanager
def real_credentials(tree_dir, config):
    """
    Give the scripts in tree_dir the server and credentials from config, as they
    would have them for a person who has filled in set_variables.local.sh.

    The values go into a temporary file that set_variables.sh reads instead of
    set_variables.local.sh (named by ST_ADMIN_LOCAL_VARIABLES, or
    ST_ENDUSER_LOCAL_VARIABLES for the EndUser tree). Nothing in the repository
    is written and your own local file is never touched, whatever happens to
    this process. The variable is put back on exit, so contexts can nest.
    """
    name = "ST_ENDUSER_LOCAL_VARIABLES" if "EndUser" in tree_dir else "ST_ADMIN_LOCAL_VARIABLES"
    content = "#!/bin/bash\n" + "".join(
        "export %s=%s\n" % (var, shlex.quote(str(config[key])))
        for var, key in (("ST_SERVER", "st_server"), ("ST_PORT", "st_port"),
                         ("ST_USER", "st_user"), ("ST_PASSWORD", "st_password")))
    fd, temp_file = tempfile.mkstemp(prefix="st_harness_", suffix=".sh")
    with os.fdopen(fd, "w") as f:
        f.write(content)
    previous = os.environ.get(name)
    os.environ[name] = temp_file
    try:
        yield
    finally:
        if previous is None:
            os.environ.pop(name, None)
        else:
            os.environ[name] = previous
        try:
            os.remove(temp_file)
        except OSError:
            pass


def run(script_path, args=None, timeout=60):
    """
    Run a shipped script from its own directory, the way its own header says
    to ("./02.accounts_POST.sh"), and return the CompletedProcess.

    Never raises on a non-zero exit, and a non-zero exit here does not by
    itself mean the API call failed: these scripts use plain curl with no
    --fail, so curl exits 0 even when the server returned 4xx or 5xx. Treat
    this as a coarse check that the script itself ran without a shell level
    error (a missing file, jq failing to parse) - confirm the real outcome
    against the API afterward, independently.
    """
    script_dir = os.path.dirname(script_path)
    script_name = os.path.basename(script_path)
    cmd = ["bash", script_name] + list(args or [])
    return subprocess.run(cmd, cwd=script_dir, capture_output=True, text=True,
                          timeout=timeout)


PY_INTERPRETER = path("tests", "local", "pyvenv", "bin", "python3")


def python_available():
    """
    True when tests/local/pyvenv has been set up - a venv holding requests
    and requests_toolbelt, the two third-party libraries the Admin API 2.0
    python3 examples need. st_client.py stays stdlib only on purpose so the
    harness itself runs on any machine; the examples it runs were written
    against requests, same as bash examples assume curl and jq are on PATH.
    Create it with:

        python3 -m venv tests/local/pyvenv
        tests/local/pyvenv/bin/pip install requests requests_toolbelt
    """
    return os.path.exists(PY_INTERPRETER)


# The python examples read a file named config, one folder above themselves, and
# there is no way to name another one, so this one is written in place. The
# original is first copied to tests/local (git ignored) with a note of where it
# goes, and put back on exit, on a kill, and by the next run if even that failed.
BACKUP_DIR = path("tests", "local", "harness_backups")
_NOTE = os.path.join(BACKUP_DIR, "python_config.target")
_ORIG = os.path.join(BACKUP_DIR, "python_config.orig")
_ABSENT = os.path.join(BACKUP_DIR, "python_config.absent")
_python_depth = 0


def restore_python_config():
    """Put back the python config a run left behind. True when there was one to put back."""
    if not os.path.exists(_NOTE):
        return False
    with open(_NOTE) as f:
        target = f.read().strip()
    if os.path.exists(_ORIG):
        shutil.copyfile(_ORIG, target)
    elif os.path.exists(_ABSENT) and os.path.exists(target):
        os.remove(target)
    for leftover in (_NOTE, _ORIG, _ABSENT):
        if os.path.exists(leftover):
            os.remove(leftover)
    return True


@contextlib.contextmanager
def real_credentials_python(tree_dir, config):
    """
    Same idea as real_credentials(), for the python3 examples: they each
    read st_server/st_port/st_user/st_password (and optionally
    st_edge_server, only stGraceful.py uses it) from a file named 'config'
    one directory above themselves, not set_variables.local.sh. The file that
    was there is kept on disk and put back, so a kill cannot lose it.
    """
    global _python_depth
    target = os.path.join(tree_dir, "config")
    if _python_depth == 0:
        restore_python_config()  # a run that was killed before this one
        os.makedirs(BACKUP_DIR, exist_ok=True)
        if os.path.exists(target):
            shutil.copyfile(target, _ORIG)
        else:
            open(_ABSENT, "w").close()
        with open(_NOTE, "w") as f:  # last, so a note means a complete backup
            f.write(target)
        outer = None
    else:
        outer = open(target).read() if os.path.exists(target) else None
    _python_depth += 1

    lines = [
        'st_server="%s"' % config["st_server"],
        'st_port="%s"' % config["st_port"],
        'st_user="%s"' % config["st_user"],
        'st_password="%s"' % config["st_password"],
    ]
    if config.get("st_edge_server"):
        lines.append('st_edge_server="%s"' % config["st_edge_server"])
    with open(target, "w") as f:
        f.write("\n".join(lines) + "\n")

    try:
        yield
    finally:
        _python_depth -= 1
        if _python_depth == 0:
            restore_python_config()
        elif outer is None:
            os.remove(target)
        else:
            with open(target, "w") as f:
                f.write(outer)


def run_python(script_path, args=None, timeout=60):
    """
    Run a shipped python3 script from its own directory, the way run() runs
    a bash script - using the venv at tests/local/pyvenv (see
    python_available()) rather than whatever python3 happens to be on PATH,
    so the third-party libraries these examples import are actually there.

    Never raises on a non-zero exit - these scripts call sys.exit(0) on many
    of their own "cannot proceed" paths, so a clean exit is not by itself
    proof of success either; confirm the real outcome against the API
    afterward, independently, the same as for the bash examples.
    """
    script_dir = os.path.dirname(script_path)
    script_name = os.path.basename(script_path)
    cmd = [PY_INTERPRETER, script_name] + list(args or [])
    return subprocess.run(cmd, cwd=script_dir, capture_output=True, text=True,
                          timeout=timeout)


def chain_substitutions(prefix, ssh_host, ssh_port):
    """
    The substitutions 31.subscriptions_routes_transfers_scripts.py applies to
    the Admin examples it runs: every fixed name they use, mapped to a
    throwaway name carrying prefix, and the partner's host and SSH port mapped
    to the configured ones. Kept here, rather than in the check, so the offline
    suite can confirm each one still applies to the scripts as they are.
    """
    return {
        '"john"': '"%schain"' % prefix,
        "${1:-john}": "${1:-%schain}" % prefix,
        "AdvancedRoutingApplication": prefix + "ARApplication",
        "SimpleRoute_Compress": prefix + "SimpleRoute_Compress",
        "SimpleRoute_Decompress": prefix + "SimpleRoute_Decompress",
        '"SimpleRouteName"': '"%sSimpleRouteName"' % prefix,
        "RouteFromPartner": prefix + "RouteTemplate",
        'PARTNER_HOST="${ST_SERVER}"': 'PARTNER_HOST="%s"' % ssh_host,
        'PARTNER_SSH_PORT="8022"': 'PARTNER_SSH_PORT="%s"' % ssh_port,
    }


def substitute(text, substitutions):
    """text with each (old, new) pair applied, the way substituted_copy() does."""
    for old, new in substitutions.items():
        text = text.replace(old, new)
    return text


def unsubstituted(text, substitutions):
    """
    The original names still in text, as whole names, after substitution. A
    name with the throwaway prefix in front of it does not count, so
    ZZTEST_SimpleRoute_Compress is not mistaken for SimpleRoute_Compress.

    A substitution that changes nothing is not counted: with the default SSH
    port, PARTNER_SSH_PORT="8022" is replaced by itself, and finding it
    afterward does not mean a real name was left behind.
    """
    return [old for old, new in substitutions.items()
            if old != new and re.search(r"(?<![A-Za-z0-9_])" + re.escape(old), text)]


@contextlib.contextmanager
def substituted_copy(script_path, substitutions):
    """
    A temporary copy of script_path with each (old, new) pair in substitutions
    applied, written next to the original so relative paths inside it (a temp
    file, a sibling folder) still resolve the way they do for the real file.

    This is for one purpose only: a hardcoded name in a shipped script - an
    account, a site, an application - collides with a real object already on
    the server the script was not written to expect. The substitution lets
    the same request bodies and the same PATCH/PUT logic be exercised against
    a name that does not collide, without ever touching the real object.

    This is not the same as running the real file. A check using this should
    say so plainly, the same way a finding about an unverified assumption is
    reported as a finding rather than presented as fact.

    Used as a context manager - the temporary file is removed on the way out,
    success or not:

        with substituted_copy(path, {"john": "john_test"}) as copy_path:
            run(copy_path)
    """
    with open(script_path) as f:
        content = substitute(f.read(), substitutions)

    script_dir = os.path.dirname(script_path)
    copy_path = os.path.join(script_dir, ".zztest_" + os.path.basename(script_path))
    with open(copy_path, "w") as f:
        f.write(content)

    try:
        yield copy_path
    finally:
        if os.path.exists(copy_path):
            os.remove(copy_path)
