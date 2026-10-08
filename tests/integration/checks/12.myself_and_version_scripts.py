#!/usr/bin/env python3
"""
Read only. Runs the actual, unmodified scripts in
Admin/API 2.0/bash/01.Authentication and Admin/API 2.0/bash/02.Introduction
against a configured server, and independently verifies what each one claims
to do - not by trusting the script's own exit code alone: each of them now
reads the HTTP status of its calls and exits 1 on one that is not 200, but the
check still reads the server's own answer for what the script printed.

No persistent object is created by any script this check runs, so this needs
no --write, the same way 01.connect.py's own login/logout cycle does not.

Deliberately excluded: 02.Introduction/04.myself_PATCH.sh. It replaces the
currently authenticated user's own password with the literal string
"TYPE_WHATEVER_YOU_WANT_HERE". Running it unmodified against the admin
account this whole suite authenticates as would lock every other check out of
that account, on this and every future run - not something to do
automatically against a real credential. It is not covered by any check.

Against --mock this passes too: the mock's /version and /myself answers carry
the `os` and `lastPasswordChangeTime` fields that 02.version_GET.sh and
03.myself_GET.sh end with a grep for, since a script's exit code is that of its
last command and a grep that finds nothing exits non-zero.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

c = st_client.Checker("Myself and version, run for real from Admin/API 2.0/bash/01.Authentication "
                       "and 02.Introduction")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
AUTH_DIR = os.path.join(BASH_TREE, "01.Authentication")
INTRO_DIR = os.path.join(BASH_TREE, "02.Introduction")
REFERER = "THIS_IS_A_RANDOM_TEXT"
USER = config.get("st_user")


def run_and_report(directory, name, timeout=60):
    result = runner.run(os.path.join(directory, name), timeout=timeout)
    c.check("%s runs without a shell level error" % name, result.returncode == 0,
            result.stderr.strip()[-300:] if result.returncode else "")
    return result


def get_with_cookie_jar(jar_path):
    """
    Issue one GET /myself using only a leftover cookie.jar a script wrote -
    never the harness's own session - so that whether a session is still
    valid is proven independently of the script's own (unchecked) claim.
    Returns the HTTP status code as a string.

    Also sends the harness client's own csrfToken. The two are unrelated
    sessions, but confirmed directly against the bundled mock, its CSRF
    check compares against one fixed, global value rather than one scoped
    per session - so the harness's own current token is valid here too. A
    real, CSRF-enabled server was confirmed separately to not enforce this
    at all on a cookie-based GET (this project's own lab is lenient the
    same way it is about the Referer header), so sending it costs nothing
    there either way.
    """
    cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-k",
           "--cookie", jar_path, "-X", "GET",
           "https://%s:%s/api/v2.0/myself" % (config.get("st_server"), config.get("st_port")),
           "-H", "accept: application/json", "-H", "Referer: %s" % REFERER]
    if getattr(client, "_csrf", None):
        cmd += ["-H", "csrfToken: %s" % client._csrf]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout.strip()


client = st_client.connect(config, c)

with runner.real_credentials(BASH_TREE, config):

    # -- 01.Authentication ----------------------------------------------------
    result = run_and_report(AUTH_DIR, "01.myself_POST.sh")
    # It sends a real login, POST /myself, which answers a confirmation and not the
    # account (GET /myself does that, see 02.Introduction/03.myself_GET.sh)
    c.check('01.myself_POST.sh logs in: the answer is a login confirmation, not account data',
            "Logged in" in result.stdout, result.stdout[-200:])

    cookie_jar = os.path.join(AUTH_DIR, "cookie.jar")
    result = run_and_report(AUTH_DIR, "01.myself_cookie_POST.sh")
    c.check("01.myself_cookie_POST.sh's own output identifies the logged in user",
            USER in result.stdout, result.stdout[-200:])
    if os.path.exists(cookie_jar):
        status = get_with_cookie_jar(cookie_jar)
        c.check("the cookie jar it wrote still authenticates on its own",
                status == "200", status)
        os.remove(cookie_jar)
    else:
        c.check("01.myself_cookie_POST.sh wrote a reusable cookie.jar", False)

    # -- 02.Introduction --------------------------------------------------------
    real_version = client.get("version").json() or {}

    result = run_and_report(INTRO_DIR, "01.version_GET.sh")
    version_value = real_version.get("version")
    c.check("01.version_GET.sh's own output contains the real version string",
            bool(version_value) and version_value in result.stdout, result.stdout[-200:])

    result = run_and_report(INTRO_DIR, "02.version_GET.sh")
    server_type = real_version.get("serverType")
    os_value = real_version.get("os")
    c.check("02.version_GET.sh's grep for serverType found the real value",
            bool(server_type) and server_type in result.stdout, result.stdout[-300:])
    c.check("02.version_GET.sh's grep for os found the real value",
            bool(os_value) and os_value in result.stdout, result.stdout[-300:])
    if version_value and "5.5" not in version_value:
        c.info('this server reports version "%s", not 5.5 - the script\'s '
               '"grep for version.*5.5" line is expected to find nothing here. '
               "That is the script demonstrating a version-specific filter, "
               "not a bug." % version_value)

    result = run_and_report(INTRO_DIR, "03.myself_GET.sh")
    c.check("03.myself_GET.sh's own output identifies the logged in user",
            USER in result.stdout, result.stdout[-200:])
    c.check("03.myself_GET.sh's grep for lastPasswordChangeTime found it",
            "lastPasswordChangeTime" in result.stdout, result.stdout[-200:])

    result = run_and_report(INTRO_DIR, "05.myself_POST.sh")
    # Confirmed directly: unlike GET /myself, POST /myself does not return the
    # account object - just a login confirmation message. Assert on that,
    # not on account data this call never returns.
    c.check('POST /myself replies with a login confirmation, not account data',
            "Logged in" in result.stdout, result.stdout[-200:])

    cookie_jar = os.path.join(INTRO_DIR, "cookie.jar")
    result = run_and_report(INTRO_DIR, "06.myself_DELETE.sh")
    c.check("06.myself_DELETE.sh's own output identifies the logged in user "
            "at least once, before logout", USER in result.stdout, result.stdout[-300:])
    if os.path.exists(cookie_jar):
        status = get_with_cookie_jar(cookie_jar)
        c.check("the session is really gone after the script's own DELETE - "
                "confirmed independently, not by trusting its unchecked final "
                "GET", status in ("401", "403"), status)
        os.remove(cookie_jar)
    else:
        c.check("06.myself_DELETE.sh wrote a cookie.jar to verify against", False)

client.logout()
c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
