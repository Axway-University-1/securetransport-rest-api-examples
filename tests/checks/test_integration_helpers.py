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
if failed:
    print("test_integration_helpers: FAIL (%d)" % failed)
    sys.exit(1)
print("test_integration_helpers: PASS")
