#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 26.LoginRestrictionPolicies
examples against throwaway policies and a throwaway business unit, and checks
each effect through the API: create (with a name with a space), list and filter,
check, read, replace, add a rule, enable, disable and remove a rule, assign and
take away a business unit, delete, and every argument each example refuses.

It checks the API, not what a policy does to a login: on the lab these examples
were written against, a policy that denied every address, assigned to a business
unit, did not stop an account of that unit logging in over FTP or the EndUser API,
so this check makes no claim about enforcement. No policy is ever made the
default, which would apply it to every account that has none of its own.

Needs --write and st_allow_writes="yes". Refuses to start when its example_lrp*
policies or its business unit exist, and removes everything in a finally block.
"""
import os
import sys
from urllib.parse import quote

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the login restriction policy examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Login restriction policies, run for real from Admin/API 2.0/bash/26.LoginRestrictionPolicies")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "26.LoginRestrictionPolicies")
NAME, SPACED, UNIT = "example_lrp", "example lrp space", "example_lrp_bu"


def script(name, args=None, expect_rc=0):
    result = runner.run(os.path.join(FOLDER, name), args, timeout=90)
    out = result.stdout + result.stderr
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc, out.strip()[-300:])
    return out


def policy(name):
    response = admin.get("loginRestrictionPolicies/" + quote(name, safe=""))
    return response.json() if response.status == 200 else None


def rule(name_, rule_name):
    return next((r for r in (policy(name_) or {}).get("rules", []) if r["name"] == rule_name), None)


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /loginRestrictionPolicies")
    admin.logout()
    sys.exit(c.done())
if policy(NAME) or policy(SPACED) or admin.exists("businessUnits/" + UNIT):
    c.check("no example_lrp* policy or business unit exists yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

try:
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        out = script("02.loginRestrictionPolicies_POST.sh")
        made = policy(NAME)
        c.check("02 created example_lrp: ALLOW_THEN_DENY, no rules, no business units, not the default",
                made and (made["type"], made["rules"], made["businessUnits"], made["isDefault"]) == ("ALLOW_THEN_DENY", [], [], False), made)
        c.check("02 printed where it is, ending with its name", "It is at" in out and out.strip().endswith("/loginRestrictionPolicies/%s" % NAME), out[-200:])
        script("02.loginRestrictionPolicies_POST.sh", [SPACED, "DENY_THEN_ALLOW", "has a space"])
        c.check("02 a name with a space, the other type, a description",
                (policy(SPACED) or {}).get("type") == "DENY_THEN_ALLOW" and policy(SPACED)["description"] == "has a space")
        script("02.loginRestrictionPolicies_POST.sh", expect_rc=1)
        total = admin.get("loginRestrictionPolicies").json()["resultSet"]["totalCount"]
        for args in (["a/b"], ["a;b"], ["x", "SIDEWAYS"], [" "]):
            script("02.loginRestrictionPolicies_POST.sh", args, expect_rc=2)
        c.check("02 a policy that exists, a bad name or type sent nothing", admin.get("loginRestrictionPolicies").json()["resultSet"]["totalCount"] == total)

        script("03.loginRestrictionPolicies_name_HEAD.sh")
        script("03.loginRestrictionPolicies_name_HEAD.sh", [SPACED])
        script("03.loginRestrictionPolicies_name_HEAD.sh", ["example_lrp_nope"], expect_rc=1)

        # ---- rules
        script("06.loginRestrictionPolicies_name_PATCH.sh")
        added = rule(NAME, "example rule")
        c.check("06 added a DENY rule for the example host name, enabled, with no condition",
                added and (added["type"], added["clientAddress"], added["isEnabled"], added["expression"]) == ("DENY", "client.example.com", True, ""), added)
        condition = "${currentSessions <= 3}"
        script("06.loginRestrictionPolicies_name_PATCH.sh", [NAME, "office", "ALLOW", "10.0.0.0/24", condition])
        office = rule(NAME, "office")
        c.check("06 an ALLOW rule for a network, with an Expression Language condition kept exactly",
                office and (office["type"], office["clientAddress"], office["expression"]) == ("ALLOW", "10.0.0.0/24", condition), office)
        script("06.loginRestrictionPolicies_name_PATCH.sh", [NAME, "office", "DENY", "*.example.com"])
        names = [r["name"] for r in policy(NAME)["rules"]]
        c.check("06 a rule whose name is already there is replaced, not added twice",
                names.count("office") == 1 and rule(NAME, "office")["type"] == "DENY" and rule(NAME, "office")["clientAddress"] == "*.example.com", names)
        before = [r["name"] for r in policy(NAME)["rules"]]
        script("06.loginRestrictionPolicies_name_PATCH.sh", [NAME, "bad", "DENY", "not an address!"], expect_rc=1)
        c.check("06 an address that is not valid is refused, and nothing is added", [r["name"] for r in policy(NAME)["rules"]] == before)
        script("06.loginRestrictionPolicies_name_PATCH.sh", [NAME, "unchecked", "DENY", "*", "${nonsense("])
        c.check("06 a condition that is not valid Expression Language is accepted: it is not checked", rule(NAME, "unchecked") is not None)
        script("06.loginRestrictionPolicies_name_PATCH.sh", [NAME, "x", "MAYBE"], expect_rc=2)
        script("06.loginRestrictionPolicies_name_PATCH.sh", [NAME, "a/b"], expect_rc=2)
        script("06.loginRestrictionPolicies_name_PATCH.sh", ["example_lrp_nope"], expect_rc=1)

        script("08.loginRestrictionPolicies_name_PATCH_rule.sh", [NAME, "office", "disable"])
        c.check("08 disabled the rule office, and only that one", rule(NAME, "office")["isEnabled"] is False and rule(NAME, "example rule")["isEnabled"] is True)
        script("08.loginRestrictionPolicies_name_PATCH_rule.sh", [NAME, "office", "enable"])
        c.check("08 enabled it again", rule(NAME, "office")["isEnabled"] is True)
        script("08.loginRestrictionPolicies_name_PATCH_rule.sh", [NAME, "unchecked", "remove"])
        c.check("08 removed the rule unchecked, and kept the others", rule(NAME, "unchecked") is None and rule(NAME, "office") and rule(NAME, "example rule"))
        script("08.loginRestrictionPolicies_name_PATCH_rule.sh", [NAME, "nosuchrule"], expect_rc=1)
        script("08.loginRestrictionPolicies_name_PATCH_rule.sh", [NAME, "office", "explode"], expect_rc=2)

        # ---- business units
        c.check("set up: a business unit", admin.post("businessUnits", {"name": UNIT, "baseFolder": "/home/%s" % UNIT}).status == 201)
        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [NAME, UNIT])
        c.check("09 assigned the policy to the business unit", policy(NAME)["businessUnits"] == [UNIT], policy(NAME)["businessUnits"])
        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [NAME, UNIT])
        c.check("09 assigning it again changes nothing", policy(NAME)["businessUnits"] == [UNIT])
        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [NAME, "example_lrp_no_such_unit"], expect_rc=1)
        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [NAME], expect_rc=2)
        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [NAME, UNIT, "sideways"], expect_rc=2)

        out = script("04.loginRestrictionPolicies_name_GET.sh")
        c.check("04 reads the policy: type, business unit and each rule",
                "  %s: ALLOW_THEN_DENY, not the default" % NAME in out and "  business units: %s" % UNIT in out
                and "    office  DENY  *.example.com  enabled  -" in out and "    example rule  DENY  client.example.com  enabled  -" in out, out[-600:])
        out = script("04.loginRestrictionPolicies_name_GET.sh", [SPACED])
        c.check("04 reads the policy with a space in its name", "  %s: DENY_THEN_ALLOW, not the default" % SPACED in out, out[-300:])

        out = script("01.loginRestrictionPolicies_GET.sh", ["example*", "DENY_THEN_ALLOW"])
        c.check("01 lists them with their rule counts and business units",
                "  %s  ALLOW_THEN_DENY  2 rule(s)  business units: %s" % (NAME, UNIT) in out and "  %s  DENY_THEN_ALLOW  0 rule(s)  business units: -" % SPACED in out, out[-600:])
        c.check("01 and only the DENY_THEN_ALLOW ones under that heading",
                out.split("Only the ones of type DENY_THEN_ALLOW:")[-1].split("The default policy")[0].count("  %s  " % NAME) == 0)
        c.check("01 neither of them is the default policy", "  %s  " % NAME not in out.split("The default policy")[-1] and "  %s  " % SPACED not in out.split("The default policy")[-1])
        script("01.loginRestrictionPolicies_GET.sh", ["*", "SIDEWAYS"], expect_rc=2)

        # ---- replace: rules and business units must survive
        old_ids = [r["id"] for r in policy(NAME)["rules"]]
        script("05.loginRestrictionPolicies_name_PUT.sh", [NAME, "replaced by the check"])
        now = policy(NAME)
        c.check("05 PUT changed the description, and kept the name, the rules and the business unit",
                now and (now["description"], now["name"], len(now["rules"]), now["businessUnits"]) == ("replaced by the check", NAME, len(old_ids), [UNIT]), now)
        c.check("05 the rules keep their ids and their order across a PUT", [r["id"] for r in now["rules"]] == old_ids, now["rules"])
        script("05.loginRestrictionPolicies_name_PUT.sh", ["example_lrp_nope"], expect_rc=1)

        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [NAME, UNIT, "remove"])
        c.check("09 took the business unit away", policy(NAME)["businessUnits"] == [])
        script("09.loginRestrictionPolicies_name_PATCH_businessUnit.sh", [NAME, UNIT, "remove"], expect_rc=1)

        c.check("no policy was made the default", not (policy(NAME) or {}).get("isDefault") and not (policy(SPACED) or {}).get("isDefault"))
        script("07.loginRestrictionPolicies_name_DELETE.sh")
        c.check("07 deleted example_lrp", policy(NAME) is None)
        script("07.loginRestrictionPolicies_name_DELETE.sh", expect_rc=1)
        script("07.loginRestrictionPolicies_name_DELETE.sh", [SPACED])
        c.check("07 deleted the policy with a space in its name", policy(SPACED) is None)
finally:
    for name in (NAME, SPACED, "x"):
        admin.delete("loginRestrictionPolicies/" + quote(name, safe=""))
    admin.delete("businessUnits/" + UNIT)
    c.check("nothing is left behind: no policy, no business unit",
            not policy(NAME) and not policy(SPACED) and not admin.exists("businessUnits/" + UNIT))
    admin.logout()

sys.exit(c.done())
