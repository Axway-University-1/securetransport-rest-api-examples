#!/usr/bin/env python3
"""
WRITES TO THE SERVER, and changes one server wide option for the length of the check, then puts it back and compares:
Users.SecretQuestion.Enabled (false on the lab). Runs EndUser/UseCases/07-secret-questions for real, as a throwaway end user:

  - with the service on and no question set: 02 exits 4 (the 503 that means "none yet", told apart from "off");
  - 00.run_all.sh WITHOUT an answer stops at 03 and changes nothing (the account still has no question);
  - with ST_SECRET_ANSWER the whole run exits 0, the question the account then has (read through the API by this
    check) is question 2 of the list when ST_SECRET_QUESTION_NUMBER=2, and 05 (three refused changes) left it so;
  - with the service switched off again, 01 and 02 exit 3.

The throwaway account takes its secret question with it. Needs --write and st_allow_writes="yes".
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "switch the secret question service on and run the use case for real")

c = st_client.Checker("EndUser use case 07-secret-questions, run for real with the service switched on")

ENDUSER_TREE = runner.path("EndUser", "API 2.0", "bash")
UC = runner.path("EndUser", "UseCases", "07-secret-questions")
OPTION = "Users.SecretQuestion.Enabled"
ACCOUNT = config.get("st_enduser_test_account", "ZZTEST_enduser") + "_sq2"
PASSWORD = harness.new_password()
ENDUSER_PORT = harness.ports(config).enduser

admin = harness.connect(config, c, mock=("the bundled mock does not implement the EndUser API on a second port; "
                                         "run this against a real server to exercise it"))
created = False
original = None


def option_values():
    result = admin.get("configurations/options", {"name": OPTION}).json().get("result", [])
    return result[0]["values"] if result else None


def set_option(values):
    return admin.put("configurations/options", [{"name": OPTION, "values": values}]).status


def run(script, **env):
    cfg = dict(config, st_port=ENDUSER_PORT, st_user=ACCOUNT, st_password=PASSWORD)
    with runner.real_credentials(ENDUSER_TREE, cfg):
        return runner.run(os.path.join(UC, script), env=env, timeout=300)


def clear_local():
    for leftover in ("session.cookie.jar", "state.local.csrf"):
        p = os.path.join(UC, leftover)
        if os.path.exists(p):
            os.remove(p)


def question_of_account():
    user = st_client.EndUserClient(config["st_server"], ENDUSER_PORT, ACCOUNT, PASSWORD)
    user.login()
    try:
        response = user._request("GET", "myself/secretQuestion")
        return response.status, (response.json() or {}).get("secretQuestion") if response.status == 200 else None
    finally:
        user.logout()


try:
    original = option_values()
    c.check("read %s: %s" % (OPTION, original), original is not None)
    if original is None or admin.exists("accounts/" + ACCOUNT):
        c.info("nothing to do (no such option, or the account name is taken)")
        admin.logout()
        sys.exit(c.done())
    response = admin.post("accounts", {
        "name": ACCOUNT, "type": "user", "uid": "1062", "gid": "1062", "homeFolder": "/home/" + ACCOUNT,
        "user": {"name": ACCOUNT, "passwordCredentials": {"password": PASSWORD}}})
    created = response.status == 201
    c.check('created a throwaway end user account "%s"' % ACCOUNT, created, response.text[:200])
    if not created:
        admin.logout()
        sys.exit(c.done())
    c.check("switched the service on", set_option(["true"]) == 204)

    r = run("01.secretQuestions_GET.sh")
    lines = r.stdout.splitlines()
    questions = [l.split("  ", 2)[2] for l in lines if l.startswith("  ") and l.strip()[:1].isdigit() and len(l.split("  ", 2)) == 3]
    c.check("01 lists the questions, numbered", r.returncode == 0 and len(questions) >= 2, (r.returncode, r.stdout[-300:]))

    r = run("02.secretQuestion_GET_mine.sh")
    c.check("02 with the service on and no question: exit 4, not 3", r.returncode == 4 and "has no secret question yet" in r.stdout, (r.returncode, r.stdout[-300:]))

    r = run("00.run_all.sh")
    c.check("00.run_all.sh without an answer stops at 03 (exit 1)", r.returncode == 1 and "03.secretQuestion_PUT failed." in r.stdout, (r.returncode, r.stdout[-300:]))
    c.check("and changed nothing: the account still has no question", question_of_account()[0] == 503, question_of_account())

    r = run("00.run_all.sh", ST_SECRET_ANSWER="zztest answer", ST_SECRET_QUESTION_NUMBER="2")
    c.check("00.run_all.sh with an answer exits 0", r.returncode == 0, (r.stdout + r.stderr)[-500:])
    c.check("it ended with the cleanup", "Cleaned up." in r.stdout, r.stdout[-200:])
    status, question = question_of_account()
    c.check("the account's question is question 2 of the list (read through the API)", status == 200 and question == (questions[1] if len(questions) > 1 else None),
            (status, question, questions[:2]))
    r = run("05.secretQuestion_PUT_refused.sh")
    c.check("05 again: three refusals, exit 0", r.returncode == 0 and r.stdout.count("HTTP 400") == 3, r.stdout[-400:])
    c.check("and the question is still the same", question_of_account() == (200, question))

    c.check("switched the service off", set_option(["false"]) == 204)
    r = run("01.secretQuestions_GET.sh")
    c.check("01 with the service off exits 3", r.returncode == 3, (r.returncode, r.stdout[-200:]))
    r = run("02.secretQuestion_GET_mine.sh")
    c.check("02 with the service off exits 3 (an account that has a question, and the service off)", r.returncode == 3, (r.returncode, r.stdout[-200:]))
finally:
    if original is not None:
        try:
            set_option(original)
            c.check("%s is back to %s" % (OPTION, original), option_values() == original, option_values())
        except Exception as e:
            c.check("restored %s" % OPTION, False, str(e))
    clear_local()
    if created:
        admin.delete("accounts/" + ACCOUNT)
        c.check('the throwaway account "%s" was removed' % ACCOUNT, not admin.exists("accounts/" + ACCOUNT))
    admin.logout()

sys.exit(c.done())
