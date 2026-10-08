#!/usr/bin/env python3
"""
Run the actual, unmodified example scripts against a configured server.

st_client.py talks to the API the way the harness thinks the examples do.
This module runs the real files instead, exactly as a person would: from the
script's own directory, picking up credentials from set_variables.local.sh.
A bug in the curl invocation itself - bad quoting, a stale field name, a
broken jq filter - is what this catches that a reimplemented client cannot.
"""
import atexit
import contextlib
import os
import re
import shutil
import signal
import subprocess

REPO_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


def path(*parts):
    """A path under the repository root, e.g. path('Admin', 'API 2.0', 'bash')."""
    return os.path.join(REPO_ROOT, *parts)


def _restore_config_file(target, backup_file, existed):
    """Restore a config file from disk backup, or remove it if it didn't exist."""
    try:
        if existed and os.path.exists(backup_file):
            shutil.copy(backup_file, target)
            os.remove(backup_file)
        elif not existed and os.path.exists(target):
            os.remove(target)
    except OSError:
        pass


def _restore_all_backups():
    """Restore any stale config file backups from a previous run that was killed."""
    backup_dir = os.path.join(REPO_ROOT, "tests", ".harness_backups")
    if not os.path.isdir(backup_dir):
        return
    for backup_file in os.listdir(backup_dir):
        if backup_file.endswith(".backup"):
            try:
                with open(os.path.join(backup_dir, backup_file), "r") as f:
                    meta = f.readline().rstrip()  # "EXISTED:TARGET"
                if ":" in meta:
                    existed, target = meta.split(":", 1)
                    existed = existed == "1"
                    backup_path = os.path.join(backup_dir, backup_file)
                    _restore_config_file(target, backup_path, existed)
            except OSError:
                pass


_restore_all_backups()


@contextlib.contextmanager
def real_credentials(tree_dir, config):
    """
    Temporarily write set_variables.local.sh in tree_dir with the server and
    credentials from config, so the scripts in that tree pick them up exactly
    as they would for a person who has configured them by hand.

    Backs up to disk (not just memory) and restores whatever was already there -
    including nothing at all - so this never overwrites a real working
    configuration, even if the process is killed.
    """
    target = os.path.join(tree_dir, "set_variables.local.sh")
    existed = os.path.exists(target)
    backup_dir = os.path.join(REPO_ROOT, "tests", ".harness_backups")
    os.makedirs(backup_dir, exist_ok=True)

    backup_file = os.path.join(backup_dir, os.path.basename(target) + ".backup")

    if existed:
        shutil.copy(target, backup_file)
        with open(backup_file + ".meta", "w") as f:
            f.write("1:%s" % target)
    else:
        with open(backup_file + ".meta", "w") as f:
            f.write("0:%s" % target)

    content = (
        "#!/bin/bash\n"
        "# Written by the integration test harness (script_runner.py).\n"
        "# Restored to what it was before on exit - see real_credentials().\n"
        'export ST_SERVER="%s"\n'
        'export ST_PORT="%s"\n'
        'export ST_USER="%s"\n'
        'export ST_PASSWORD="%s"\n'
    ) % (config["st_server"], config["st_port"], config["st_user"], config["st_password"])

    with open(target, "w") as f:
        f.write(content)

    def cleanup_credentials():
        _restore_config_file(target, backup_file, existed)
        try:
            os.remove(backup_file + ".meta")
        except OSError:
            pass

    # Register cleanup for normal exit, SIGTERM, and SIGINT
    atexit.register(cleanup_credentials)
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda s, f: (cleanup_credentials(), exit(128 + sig)))

    try:
        yield
    finally:
        cleanup_credentials()


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


@contextlib.contextmanager
def real_credentials_python(tree_dir, config):
    """
    Same idea as real_credentials(), for the python3 examples: they each
    read st_server/st_port/st_user/st_password (and optionally
    st_edge_server, only stGraceful.py uses it) from a file named 'config'
    one directory above themselves - not set_variables.local.sh. Backs up
    to disk and restores whatever was already there, including nothing at all.
    """
    target = os.path.join(tree_dir, "config")
    existed = os.path.exists(target)
    backup_dir = os.path.join(REPO_ROOT, "tests", ".harness_backups")
    os.makedirs(backup_dir, exist_ok=True)

    backup_file = os.path.join(backup_dir, "python_config.backup")

    if existed:
        shutil.copy(target, backup_file)
        with open(backup_file + ".meta", "w") as f:
            f.write("1:%s" % target)
    else:
        with open(backup_file + ".meta", "w") as f:
            f.write("0:%s" % target)

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

    def cleanup_python_config():
        _restore_config_file(target, backup_file, existed)
        try:
            os.remove(backup_file + ".meta")
        except OSError:
            pass

    atexit.register(cleanup_python_config)

    try:
        yield
    finally:
        cleanup_python_config()


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
