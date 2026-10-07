#!/usr/bin/env python3
"""
Every example says how much it can change on the server, in a 'Risk:' line of
its header, and its bat twin says the same. tools/list_examples.py reads that
line for other projects (the trainer kit), so a missing or unknown level, or a
read that writes, is caught here.

Runs offline. Exit code 0 means clean.
"""
import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools"))
import list_examples as le  # noqa: E402

failed = 0


def chk(label, condition, detail=""):
    global failed
    if condition:
        print("  PASS  " + label)
    else:
        failed += 1
        print("  FAIL  " + label + (("  got: " + str(detail)) if detail else ""))


items = le.examples()
chk("examples are found in all three trees", {e["api"] for e in items} == {"admin", "enduser", "feature"} and len(items) > 250, len(items))

missing = [e["path"] for e in items if e["risk"] is None]
chk("every example has exactly one Risk line", not missing, missing[:5])
unknown = [(e["path"], e["risk"]) for e in items if e["risk"] and e["risk"] not in le.LEVELS]
chk("every Risk is one of read, write, config, disruptive", not unknown, unknown[:5])

mismatch = []
for e in items:
    if e["bat"]:
        level, note = le.risk_of(open(os.path.join(REPO, e["bat"])).read())
        if (level, note) != (e["risk"], e["risk_note"]):
            mismatch.append(e["bat"])
chk("every bat twin carries the same Risk line as its bash example", not mismatch, mismatch[:5])

reads_that_write = [e["path"] for e in items if e["method"] in ("GET", "HEAD") and e["risk"] != "read"]
chk("a GET or HEAD example is a read", not reads_that_write, reads_that_write[:5])
# POSTs that change nothing: logins, logouts, connection tests, a checksum
READ_POSTS = ("myself_POST", "myself_cookie_POST", "myself_DELETE", "_POST_test", "POST_md5calc")
writes_called_read = [e["path"] for e in items if e["method"] in ("POST", "PUT", "PATCH", "DELETE") and e["risk"] == "read"
                      and not any(k in e["path"] for k in READ_POSTS)]
chk("a POST, PUT, PATCH or DELETE is a read only when it is a login, logout or test", not writes_called_read, writes_called_read[:5])

disruptive = sorted(os.path.basename(e["path"]) for e in items if e["risk"] == "disruptive")
chk("the disruptive ones are exactly the daemon and server operations, maintenance mode and the keystore password",
    disruptive == ["05.daemons_operations_POST.sh", "13.servers_operations_POST.sh",
                   "25.configurations_maintenance_operations_POST.sh", "28.configurations_keystorePassword_PUT.sh"], disruptive)
chk("every disruptive or config example of the Admin API says why, or is in a config topic",
    all(e["risk_note"] or e["topic"] in ("13.Configurations", "17.AccessPolicies") for e in items if e["risk"] in ("config", "disruptive")))

denied = next(e for e in items if e["path"].endswith("22.DeniedUsers/02.deniedUsers_POST.sh"))
chk("list_examples reads the method, endpoint, usage and twin of an example",
    (denied["method"], denied["endpoint"], denied["usage"], denied["bat"], denied["topic"])
    == ("POST", "/deniedUsers", ["./02.deniedUsers_POST.sh [LOGIN_NAME [HOURS [NOTE]]]"],
        "Admin/API 2.0/bat/22.DeniedUsers/02.deniedUsers_POST.bat", "22.DeniedUsers"), denied)

print("check_risk_headers: %s" % ("PASS" if not failed else "%d FAILED" % failed))
sys.exit(1 if failed else 0)
