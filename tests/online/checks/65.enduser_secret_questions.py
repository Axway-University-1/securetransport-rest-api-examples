#!/usr/bin/env python3
"""
WRITES TO THE SERVER, and changes one server wide option for the length of the check, then puts it
back and compares: Users.SecretQuestion.Enabled, false on the lab. With it off, every secret question
call answers 503 and only the "not enabled" branch of the scripts can run, so this switches it on, runs
the scripts for real as a throwaway end user, switches it off again to see that branch too, and
restores the option to exactly what it was (and asserts it).

What it checks, in EndUser/API 2.0/bash:
  - 07.SecretQuestions/01 lists the questions, 03 prints one on its own (standard output only), and
    02 says a listed question is on the list and an invented one is not;
  - 03.Myself/06 for an account with no question: the server answers 503 "Service not available", the
    same as for a disabled service, and the script tells them apart (exit 4, not 3);
  - 03.Myself/07 sets a question, 06 reads it back, and a question that is not on the list is refused;
  - with the service switched off again, 01, 02, 03 and 06 exit 3.

Needs --write and st_allow_writes="yes". The end user port is the one the other EndUser checks use.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "switch the secret question service on and run the scripts for real")

c = st_client.Checker("EndUser secret questions, run for real with the service switched on")

ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
SQ = os.path.join(ENDUSER_TREE, "07.SecretQuestions")
ME = os.path.join(ENDUSER_TREE, "03.Myself")
OPTION = "Users.SecretQuestion.Enabled"
ACCOUNT = config.get("st_enduser_test_account", "ZZTEST_enduser") + "_sq"
ACCOUNT_PASSWORD = harness.new_password()
ENDUSER_PORT = harness.ports(config).enduser

admin = harness.connect(config, c, mock=("the bundled mock does not implement the EndUser API on a second port; "
                                         "run this against a real server to exercise it"))
created = False
original = None
COOKIE_JAR = os.path.join(ENDUSER_TREE, "myCookie.jar")
developers_jar = open(COOKIE_JAR, "rb").read() if os.path.exists(COOKIE_JAR) else None
# The scripts use the session in this jar when it is active, and it would be the developer's: start with none, put it back at the end
if developers_jar is not None:
    os.remove(COOKIE_JAR)


def option_values():
    result = admin.get("configurations/options", {"name": OPTION}).json().get("result", [])
    return result[0]["values"] if result else None


def set_option(values):
    return admin.put("configurations/options", [{"name": OPTION, "values": values}]).status


def run(script, args=None):
    return runner.run(script, args or [])


try:
    original = option_values()
    c.check("read %s: %s" % (OPTION, original), original is not None)
    if original is None:
        admin.logout()
        sys.exit(c.done())
    if admin.exists("accounts/" + ACCOUNT):
        c.info('an account named "%s" already exists; skipping rather than reuse it' % ACCOUNT)
        admin.logout()
        sys.exit(c.done())
    response = admin.post("accounts", {
        "name": ACCOUNT, "type": "user", "uid": "1054", "gid": "1054", "homeFolder": "/home/" + ACCOUNT,
        "user": {"name": ACCOUNT, "passwordCredentials": {"password": ACCOUNT_PASSWORD}}})
    created = response.status == 201
    c.check('created a throwaway end user account "%s"' % ACCOUNT, created, response.text[:200])
    if not created:
        admin.logout()
        sys.exit(c.done())
    c.check("switched the service on", set_option(["true"]) == 204)

    eu_config = dict(config, st_port=ENDUSER_PORT, st_user=ACCOUNT, st_password=ACCOUNT_PASSWORD)
    with runner.real_credentials(ENDUSER_TREE, eu_config):
        # -- the list ---------------------------------------------------------
        r = run(os.path.join(SQ, "01.secretQuestions_GET.sh"))
        # the login that may come first prints indented lines of its own: the questions follow the header
        lines = r.stdout.splitlines()
        header = lines.index("The secret questions to choose from:") if "The secret questions to choose from:" in lines else len(lines)
        questions = [l[2:] for l in lines[header + 1:] if l.startswith("  ")]
        c.check("01 lists the questions on offer", r.returncode == 0 and len(questions) > 0, r.stdout[-300:])
        r = run(os.path.join(SQ, "03.secretQuestions_GET_pick.sh"), ["1"])
        picked = r.stdout.strip()
        c.check("03 prints the first question, and only that on standard output",
                r.returncode == 0 and picked == (questions[0] if questions else None), (r.stdout, r.stderr[-200:]))
        r = run(os.path.join(SQ, "03.secretQuestions_GET_pick.sh"), [str(len(questions) + 1)])
        c.check("03 past the end of the list exits 1", r.returncode == 1, r.returncode)
        r = run(os.path.join(SQ, "02.secretQuestions_GET_check.sh"), [picked])
        c.check("02 says a question of the list is on it", r.returncode == 0 and "On the list" in r.stdout, r.stdout[-200:])
        r = run(os.path.join(SQ, "02.secretQuestions_GET_check.sh"), ["Is this question on the list?"])
        c.check("02 says an invented one is not (exit 1)", r.returncode == 1 and "Not on the list" in r.stdout, r.stdout[-200:])

        # -- an account with no question yet -----------------------------------
        r = run(os.path.join(ME, "06.myself_secretQuestion_GET.sh"))
        c.check("06 with the service on and no question set: exit 4, not 3",
                r.returncode == 4 and "has no secret question yet" in r.stdout, (r.returncode, r.stdout[-300:]))

        # -- set one, read it back, a bad one is refused -----------------------
        r = run(os.path.join(ME, "07.myself_secretQuestion_PUT.sh"), [picked, "zztest answer"])
        c.check("07 sets the question", r.returncode == 0, (r.stdout + r.stderr)[-300:])
        r = run(os.path.join(ME, "06.myself_secretQuestion_GET.sh"))
        c.check("06 reads it back", r.returncode == 0 and picked in r.stdout, r.stdout[-300:])
        r = run(os.path.join(ME, "07.myself_secretQuestion_PUT.sh"), ["Is this question on the list?", "x"])
        c.check("07 with a question that is not on the list is refused (exit 1)", r.returncode == 1, (r.returncode, r.stdout[-300:]))
        r = run(os.path.join(ME, "06.myself_secretQuestion_GET.sh"))
        c.check("and the question is still the one that was set", r.returncode == 0 and picked in r.stdout, r.stdout[-300:])

        # -- switched off again: the other branch -------------------------------
        c.check("switched the service off", set_option(["false"]) == 204)
        for label, script, args in (("01", os.path.join(SQ, "01.secretQuestions_GET.sh"), []),
                                    ("02", os.path.join(SQ, "02.secretQuestions_GET_check.sh"), [picked]),
                                    ("03", os.path.join(SQ, "03.secretQuestions_GET_pick.sh"), []),
                                    ("06", os.path.join(ME, "06.myself_secretQuestion_GET.sh"), [])):
            r = run(script, args)
            c.check("%s with the service off exits 3" % label, r.returncode == 3, (r.returncode, r.stdout[-200:], r.stderr[-200:]))
finally:
    if original is not None:
        try:
            set_option(original)
            c.check("%s is back to %s" % (OPTION, original), option_values() == original, option_values())
        except Exception as e:  # keep going: the account still has to go
            c.check("restored %s" % OPTION, False, str(e))
    if developers_jar is not None:
        with open(COOKIE_JAR, "wb") as f:
            f.write(developers_jar)
    elif os.path.exists(COOKIE_JAR):
        os.remove(COOKIE_JAR)
    if created:
        admin.delete("accounts/" + ACCOUNT)
        c.check('the throwaway account "%s" was removed' % ACCOUNT, not admin.exists("accounts/" + ACCOUNT))
    admin.logout()

sys.exit(c.done())
