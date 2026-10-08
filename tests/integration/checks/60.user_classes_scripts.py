#!/usr/bin/env python3
"""
WRITES TO THE SERVER (throwaway user classes and accounts only). Runs the real,
unmodified 36.UserClasses examples, and shows what a user class DOES: a class
decides which class an account is in when it logs in, and the class an account
landed in is visible as the `userClass` of its session.

Two throwaway accounts, one whose name a class is made for (the MATCH account)
and one it is not (the OTHER account); both log in over SFTP (the system sftp client, SSH_ASKPASS) and HTTP (an EndUser API login kept open) as the CORE logins, and over FTP (ftplib) as the legacy, additional part, after every
change, and the session list is read for the class of THAT new login.

  - 01 lists the classes in the order they are tried (the server's list is not in
    that order), counts them, filters by name and type.
  - 02 creates a class: disabled by default (the login stays in VirtClass), the new
    class goes FIRST (order 1) and VirtClass and RealClass move down; it refuses an
    enabled class for every user name, an invalid expression is the server's 400.
  - 05 and 06 enable it, change the expression, userName, userType, and the order;
    each time the next login of the MATCH account is in the class or not, and the
    OTHER account's never is. Of two classes that fit, the lower order wins.
  - 07 deletes one, never VirtClass or RealClass. A session that was open when its
    class was deleted keeps the class's name; the next login is in the next class
    that fits. A template account that names the class keeps the name.
  - 03 and 04 check and read one. The raw API: a PUT with the five required fields
    only resets expression and enabled; unknown ids are 404 (GET, HEAD) and 400
    (PUT, PATCH, DELETE); the expression is checked when saved.

Membership by a directory attribute (an LDAP login, `memberof(...)`) is NOT shown:
the lab has no directory login, and an account's own attributes are not visible
to an expression.

The accounts get a new name and user id on every run (the home folder of a deleted
account stays on disk with its first owner). Needs --write and st_allow_writes="yes".
Refuses to start when a class named example_* (in any capitals) exists. Removes what
it made in a finally block and ends by comparing the whole list of classes (with
VirtClass and RealClass, and their order) with the one saved before.
"""
import base64
import os
import random
import shutil
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402
import protocol_logins  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the user classes examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("User classes, run for real from Admin/API 2.0/bash/36.UserClasses")
_check = c.check
LABEL = [""]


def labelled(label, condition, detail=""):
    return _check(LABEL[0] + label, condition, detail)


c.check = labelled
BASH = runner.path("Admin", "API 2.0", "bash")
FOLDER = os.path.join(BASH, "36.UserClasses")
SUFFIX = "%04x%04x" % (random.randint(0, 0xFFFF), random.randint(0, 0xFFFF))
MATCH, OTHER, TEMPLATE_BASE = "example_ucm_" + SUFFIX, "example_uco_" + SUFFIX, "example_uct_" + SUFFIX
TEMPLATE = TEMPLATE_BASE
TEMPLATE_NO_CLASS_BASE = "example_ucn_" + SUFFIX
TEMPLATE_NO_CLASS = TEMPLATE_NO_CLASS_BASE
BASE_UID = random.randint(50000, 58000)
PASSWORD = "Ax" + base64.b32encode(os.urandom(9)).decode().rstrip("=") + "1!"
HOST = config["st_server"]
FIRST, SECOND, RENAMED = "example_userclass", "example_second", "example_renamed"
UPPER = "EXAMPLE_USERCLASS"
BUILTIN = ("VirtClass", "RealClass")
tracked = set()


def wait_until(predicate, seconds=30, interval=1):
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            if predicate():
                return True
        except st_client.STError:
            pass
        time.sleep(interval)
    try:
        return bool(predicate())
    except st_client.STError:
        return False


def script(name, args=None, expect_rc=0, retry=True):
    """Run an example. A list of classes can lack one that exists, so a lookup that found none for a class that is
    known to exist (retry=True) is run again, up to five times."""
    for _ in range(5):
        result = runner.run(os.path.join(FOLDER, name), args, timeout=120)
        out = result.stdout + result.stderr
        if retry and "Found 0 user classes named" in out:
            time.sleep(2)
            continue
        break
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc, out.strip()[-400:])
    return out


def classes():
    response = admin.get("userClasses", params={"limit": 0})
    return (response.json() or {}).get("result", []) if response.status == 200 else []


def find(name):
    found = [k for k in classes() if k["className"] == name]
    return found[0] if len(found) == 1 else None


def settled(name, condition, seconds=20):
    last = [None]

    def look():
        last[0] = find(name)
        return last[0] is not None and condition(last[0])
    wait_until(look, seconds)
    return last[0] or {}


def names_by_order():
    return [k["className"] for k in sorted(classes(), key=lambda k: k["order"])]


def sessions():
    response = admin.get("sessions")
    return response.json() if response.status == 200 and isinstance(response.json(), list) else []


PROTOCOLS = protocol_logins.PROTOCOLS               # SFTP, HTTP, then FTP, the legacy one, as a labelled additional part
SESSION_PROTOCOL = protocol_logins.SESSION_PROTOCOL
PROTO = "SFTP"
ENDUSER_PORT = None
logins = None                                       # the shared protocol_logins.Logins, made once the ports are known


def login(account, hold=False, proto=None):
    """Log in and return (the session of THAT login, or None when it never shows; the Holder when hold=True, else the
    login is closed). The session is the one whose id was not there before: the list is unstable and a closed session lingers."""
    proto = proto or PROTO
    before = {s["id"] for s in sessions() if s["userName"] == account}
    holder = logins.open_login(proto, account)
    found = []

    def seen():
        found[:] = [s for s in sessions() if s["userName"] == account and s["id"] not in before
                    and s["protocol"] == SESSION_PROTOCOL[proto]]
        return bool(found)
    wait_until(seen, 20)
    if hold:
        return (found[0] if found else None), holder
    holder.close()
    return found[0] if found else None


def login_class(account, hold=False):
    session = login(account, hold)
    if hold:
        return session[0] and session[0]["userClass"], session[0] and session[0]["id"], session[1]
    return session and session["userClass"]


def lands_in(account, want, seconds=30):
    """True once a new login of the account is in the class `want`; the last class seen is returned too."""
    last = [None]

    def look():
        last[0] = login_class(account)
        return last[0] == want
    return wait_until(look, seconds, 1), last[0]


def create_account(name, uid):
    response = admin.post("accounts", {"name": name, "type": "user", "uid": str(uid), "gid": str(uid), "homeFolder": "/home/" + name,
                                       "user": {"name": name, "passwordCredentials": {"password": PASSWORD}}})
    c.check("set up: the account " + name, response.status == 201, response.text[:200])


def line(k):
    return "  %d  %s  %s  user %s  group %s  address %s  %s  expression %s" % (
        k["order"], k["className"], k["userType"], k["userName"], k["group"], k["address"],
        "enabled" if k["enabled"] else "disabled", k["expression"] or "-")


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /userClasses, /sessions or the protocol servers")
    admin.logout()
    sys.exit(c.done())
if any(k["className"].lower().startswith("example_") for k in classes()):
    c.check("no user class named example_* exists yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())
servers = admin.get("servers").json()
servers = servers if isinstance(servers, list) else servers.get("result", [])
ports = {}
for protocol in ("ftp", "ssh"):
    found_ports = [x["port"] for x in servers if x.get("protocol") == protocol and x.get("port")]
    ports[protocol] = found_ports[0] if found_ports else None
daemons = admin.get("daemons").json()
ENDUSER_PORT = config.get("st_enduser_port") or str(int(config["st_port"]) - 1)
FTP_PORT, SSH_PORT = ports["ftp"], ports["ssh"]
missing = []
if not FTP_PORT or daemons.get("ftpStatus") != "Running":
    missing.append("the FTP daemon is not running")
if not SSH_PORT or daemons.get("sshStatus") != "Running":
    missing.append("the SSH daemon is not running (SFTP)")
if not shutil.which("sftp"):
    missing.append("there is no sftp client on this machine")
if missing:
    c.check("every protocol can be exercised (SFTP and HTTP are core, FTP legacy)", False, "; ".join(missing))
    admin.logout()
    sys.exit(c.done())

logins = protocol_logins.Logins(HOST, SSH_PORT, ENDUSER_PORT, FTP_PORT, PASSWORD)
saved = {k["id"]: k for k in classes()}
c.check("set up: the server has VirtClass and RealClass, and they are saved to compare with at the end",
        all(any(k["className"] == b for k in saved.values()) for b in BUILTIN), sorted(k["className"] for k in saved.values()))
open_clients = []
accounts = []
try:
    for offset, account in enumerate((MATCH, OTHER)):
        create_account(account, BASE_UID + offset)
        accounts.append(account)
    in_class, _ = lands_in(MATCH, "VirtClass")
    c.check("with no class of ours both accounts log in to VirtClass", in_class and login_class(OTHER) == "VirtClass")

    with runner.real_credentials(BASH, config):
        # -- 01 ---------------------------------------------------------------------------
        c.info("--- 01 lists the classes in the order they are tried")
        out = script("01.userClasses_GET.sh")
        now = sorted(classes(), key=lambda k: k["order"])
        c.check("01 counts the classes the API counts", "User classes on the server: %d" % len(now) in out, out[:200])
        c.check("01 prints one line per class, in the order of `order` (VirtClass before RealClass)",
                all(line(k) in out for k in now) and out.index("VirtClass") < out.index("RealClass"), out[-500:])
        out = script("01.userClasses_GET.sh", ["*", "real"])
        c.check("01 with a type: the real classes only", "RealClass" in out and "VirtClass" not in out, out[-300:])
        out = script("01.userClasses_GET.sh", ["virt*", "virtual"])
        c.check("01 a name pattern in small letters finds VirtClass (the filter ignores case)", "  VirtClass  virtual" in out and "RealClass" not in out, out[-300:])
        script("01.userClasses_GET.sh", ["*", "nope"], expect_rc=2)

        # -- 02 ---------------------------------------------------------------------------
        c.info("--- 02 creates a class, disabled by default, first in line")
        out = script("02.userClasses_POST.sh", [FIRST, MATCH])
        tracked.add(FIRST)
        first = settled(FIRST, lambda k: True)
        c.check("02 says HTTP 201 and where it is", "HTTP 201" in out and "/userClasses/%s" % first.get("id") in out, out[-300:])
        c.check("02 the class is as asked: type *, user name the MATCH account, group and address *, disabled, no expression",
                (first.get("userType"), first.get("userName"), first.get("group"), first.get("address"), first.get("enabled"), first.get("expression"))
                == ("*", MATCH, "*", "*", False, ""), first)
        c.check("02 it is FIRST (order 1) and VirtClass and RealClass moved down, in the same order",
                wait_until(lambda: names_by_order() == [FIRST, "VirtClass", "RealClass"]), names_by_order())
        c.check("the effect: the class is disabled, so the MATCH account still logs in to VirtClass", login_class(MATCH) == "VirtClass")
        before_count = len(classes())
        script("02.userClasses_POST.sh", [FIRST, MATCH], expect_rc=1)
        script("02.userClasses_POST.sh", ["example_bad", MATCH, "1==1"], expect_rc=1)
        out = script("02.userClasses_POST.sh", ["example_star", "*", "true", "true"], expect_rc=2)
        c.check("02 an enabled class for every user name is refused, nothing sent", "Refused" in out and len(classes()) == before_count, out[-200:])
        for bad in (["", MATCH, "none", "maybe"], ["example_t", MATCH, "none", "false", "bogus"], ["a b", MATCH]):
            script("02.userClasses_POST.sh", bad, expect_rc=2)
        c.check("02 the refusals and the 409 and the 400 created nothing", len(classes()) == before_count and find("example_bad") is None and find("example_star") is None)
        out = script("02.userClasses_POST.sh", [UPPER, MATCH], expect_rc=0)
        tracked.add(UPPER)
        c.check("02 a name in other capitals is another class (names are case sensitive)", find(UPPER) is not None and find(FIRST) is not None, out[-200:])
        script("07.userClasses_id_DELETE.sh", [UPPER])
        c.check("07 deleted that one only: example_userclass is still there", wait_until(lambda: find(UPPER) is None) and find(FIRST) is not None)

        # -- 03, 04 ---------------------------------------------------------------------------
        c.info("--- 03 and 04 check and read it")
        out = script("03.userClasses_id_HEAD.sh", [FIRST])
        c.check("03 says it exists, with the id", "The user class %s exists, id %s." % (FIRST, find(FIRST)["id"]) in out, out[-200:])
        script("03.userClasses_id_HEAD.sh", ["example_nosuch"], expect_rc=1)
        out = script("04.userClasses_id_GET.sh", [FIRST])
        c.check("04 prints the summary", all(t in out for t in ("  order:      1", "  type:       *", "  user name:  " + MATCH, "  enabled:    false", "  expression: -")), out[-500:])
        c.check("04 and only some fields", '"className" : "%s"' % FIRST in out.split("Only some fields of it:")[-1] and '"userName"' not in out.split("Only some fields of it:")[-1], out[-200:])
        script("04.userClasses_id_GET.sh", ["example_nosuch"], expect_rc=1)
        gid = find(FIRST)["id"]
        head = admin.head("userClasses/" + gid)
        c.check("HEAD of the id is 200; of an unknown id 404; the name in the path is no id (404)",
                head.status == 200 and admin.head("userClasses/nosuch").status == 404 and admin.get("userClasses/" + FIRST).status == 404)
        gone = admin.get("userClasses/nosuch")
        c.check("GET of an unknown id is a JSON 404 'does not exist'", gone.status == 404 and "does not exist" in gone.text, gone.text[:200])
        c.check("PUT, PATCH and DELETE of an unknown id are 400, not 404 (the reference lists 404)",
                (admin.put("userClasses/nosuch", {"className": "example_zz", "userType": "*", "userName": "x", "group": "*", "address": "*"}).status,
                 admin.patch("userClasses/nosuch", [{"op": "replace", "path": "/enabled", "value": True}]).status,
                 admin.delete("userClasses/nosuch").status) == (400, 400, 400))

        for number, PROTO in enumerate(PROTOCOLS):
            LABEL[0] = PROTO + ": "
            if PROTO == "FTP":
                c.info("--- FTP: the legacy protocol, as an additional part; the same behaviours as above")
            TEMPLATE = TEMPLATE_BASE + "_" + PROTO.lower()
            TEMPLATE_NO_CLASS = TEMPLATE_NO_CLASS_BASE + "_" + PROTO.lower()
            UID_T = BASE_UID + 2 + 2 * number
            if number:
                # the first protocol deleted the classes it used: a new disabled one, as 02 makes it
                script("02.userClasses_POST.sh", [FIRST, MATCH])
                tracked.add(FIRST)
                gid = settled(FIRST, lambda k: True).get("id")
            # -- 06 enable, 05 expression -----------------------------------------------------------
            c.info("--- 06 and 05 switch it on and off: the effect is on the NEXT login")
            out = script("06.userClasses_id_PATCH.sh", [FIRST])
            c.check("06 enables it (default): says the value before, HTTP 204", "The enabled of %s is now 'false'." % FIRST in out and "HTTP 204" in out, out[-300:])
            c.check("the class is enabled, nothing else changed", settled(FIRST, lambda k: k["enabled"]).get("userName") == MATCH)
            ok, got = lands_in(MATCH, FIRST)
            c.check("the effect: the MATCH account now logs in to %s" % FIRST, ok, got)
            c.check("and the OTHER account, whose name does not fit, is still in VirtClass", login_class(OTHER) == "VirtClass")
            out = script("05.userClasses_id_PUT.sh", [FIRST, "false"])
            c.check("05 sets the expression to false: says the values before, HTTP 204",
                    "The expression of %s is now '', enabled is true." % FIRST in out and "HTTP 204" in out, out[-300:])
            k = settled(FIRST, lambda k: k["expression"] == "false")
            c.check("the expression is false, the class still enabled, the rest as it was, and order unchanged",
                    (k.get("expression"), k.get("enabled"), k.get("userName"), k.get("userType"), k.get("order")) == ("false", True, MATCH, "*", 1), k)
            ok, got = lands_in(MATCH, "VirtClass")
            c.check("the effect: the expression is false, so the MATCH account is back in VirtClass", ok, got)
            script("05.userClasses_id_PUT.sh", [FIRST, "true or false", "-"])
            ok, got = lands_in(MATCH, FIRST)
            c.check("05 an expression that is true ('true or false', enabled left alone): in the class again", ok, got)
            script("05.userClasses_id_PUT.sh", [FIRST, "-", "false"])
            ok, got = lands_in(MATCH, "VirtClass")
            c.check("05 enabled false (expression left alone): back in VirtClass", ok and settled(FIRST, lambda k: not k["enabled"]).get("expression") == "true or false", got)
            script("05.userClasses_id_PUT.sh", [FIRST, "none", "true"])
            k = settled(FIRST, lambda k: k["enabled"])
            c.check("05 none empties the expression, enabled true", (k.get("expression"), k.get("enabled")) == ("", True), k)
            ok, got = lands_in(MATCH, FIRST)
            c.check("the effect: no expression and enabled, so it fits again", ok, got)
            before_put = find(FIRST)
            out = script("05.userClasses_id_PUT.sh", [FIRST, "1==1"], expect_rc=1)
            c.check("05 an invalid expression is the server's 400, 'is not valid', and the class is unchanged",
                    "HTTP 400" in out and "expression 1==1 is not valid." in out and find(FIRST) == before_put, out[-300:])
            script("05.userClasses_id_PUT.sh", [FIRST, "-", "-"], expect_rc=2)
            script("05.userClasses_id_PUT.sh", [FIRST, "true", "maybe"], expect_rc=2)
            script("05.userClasses_id_PUT.sh", ["example_nosuch", "true"], expect_rc=1)
            c.check("05 whatever it sent, the class id and its name are as before", find(FIRST)["id"] == gid)

            # a raw PUT of only the five required fields resets the optional ones
            raw = admin.put("userClasses/" + gid, {"className": FIRST, "userType": "*", "userName": MATCH, "group": "*", "address": "*"})
            k = settled(FIRST, lambda k: not k["enabled"])
            c.check("raw PUT of only the five required fields: 204, and it RESETS expression to '' and enabled to false (order kept)",
                    raw.status == 204 and (k.get("expression"), k.get("enabled"), k.get("order")) == ("", False, 1), (raw.status, k))
            miss = admin.put("userClasses/" + gid, {"className": FIRST, "userType": "*", "userName": MATCH, "group": "*"})
            c.check("raw PUT without `address` is 400 and says which field", miss.status == 400 and "address must not be null" in miss.text, miss.text[:200])
            script("06.userClasses_id_PATCH.sh", [FIRST, "enabled", "true"])
            c.check("set up: enabled again", settled(FIRST, lambda k: k["enabled"]).get("enabled") is True)

            # -- 06 other fields --------------------------------------------------------------------
            c.info("--- 06 changes the user name, the type, the expression")
            out = script("06.userClasses_id_PATCH.sh", [FIRST, "userName", OTHER])
            c.check("06 userName: says the value before", "The userName of %s is now '%s'." % (FIRST, MATCH) in out, out[-200:])
            ok, got = lands_in(MATCH, "VirtClass")
            c.check("the effect: the class now fits the OTHER account's name, so the MATCH account is in VirtClass", ok, got)
            ok, got = lands_in(OTHER, FIRST)
            c.check("and the OTHER account is in the class", ok, got)
            script("06.userClasses_id_PATCH.sh", [FIRST, "userName", MATCH])
            script("06.userClasses_id_PATCH.sh", [FIRST, "userType", "real"])
            ok, got = lands_in(MATCH, "VirtClass")
            c.check("06 userType real: a local (virtual) account does not fit a real class", ok, got)
            script("06.userClasses_id_PATCH.sh", [FIRST, "userType", "virtual"])
            ok, got = lands_in(MATCH, FIRST)
            c.check("06 userType virtual: it fits", ok, got)
            script("06.userClasses_id_PATCH.sh", [FIRST, "userType", "*"])
            script("06.userClasses_id_PATCH.sh", [FIRST, "expression", "false"])
            ok, got = lands_in(MATCH, "VirtClass")
            c.check("06 expression false: out of the class", ok, got)
            script("06.userClasses_id_PATCH.sh", [FIRST, "expression", "none"])
            ok, got = lands_in(MATCH, FIRST)
            c.check("06 none empties the expression: in the class", ok and settled(FIRST, lambda k: k["expression"] == "").get("expression") == "", got)
            out = script("06.userClasses_id_PATCH.sh", [FIRST, "expression", "nonsense("], expect_rc=1)
            c.check("06 an invalid expression is the server's 400 and the class is unchanged", "HTTP 400" in out and "is not valid" in out and find(FIRST)["expression"] == "", out[-300:])
            for bad in ([FIRST, "nope", "x"], [FIRST, "enabled", "maybe"], [FIRST, "order", "0"], [FIRST, "order", "x"]):
                script("06.userClasses_id_PATCH.sh", bad, expect_rc=2)
            out = script("06.userClasses_id_PATCH.sh", [FIRST, "className", RENAMED])
            tracked.add(RENAMED)
            ok, got = lands_in(MATCH, RENAMED)
            c.check("06 className renames it: the next login of the MATCH account shows the new name", ok and "The className of %s is now '%s'." % (FIRST, FIRST) in out, (got, out[-200:]))
            script("06.userClasses_id_PATCH.sh", [RENAMED, "className", FIRST])
            ok, got = lands_in(MATCH, FIRST)
            c.check("06 and back", ok, got)
            out = script("06.userClasses_id_PATCH.sh", [FIRST, "order", "99"], expect_rc=1)
            c.check("06 an order past the last class is 400 'Order is not valid.'", "Order is not valid." in out and find(FIRST)["order"] == 1, out[-300:])

            # -- expressions as they are evaluated at login, and the address ---------------------------
            for text in ("true", "1 > 0", "true or false"):
                script("06.userClasses_id_PATCH.sh", [FIRST, "expression", text])
                ok, got = lands_in(MATCH, FIRST)
                c.check("expression %s is true at login -> in the class" % text, ok, got)
            for text in ("false", "2 > 3", "not true", 'isset("LDAP_DIR_memberOf") ? true : false'):
                script("06.userClasses_id_PATCH.sh", [FIRST, "expression", text])
                ok, got = lands_in(MATCH, "VirtClass")
                c.check("expression %s is false at login -> VirtClass" % text, ok, got)
            script("06.userClasses_id_PATCH.sh", [FIRST, "expression", "none"])
            seen_session = login(MATCH)
            client_address = seen_session["host"] if seen_session else None
            c.check("the session shows the client's address", bool(client_address), seen_session)
            script("06.userClasses_id_PATCH.sh", [FIRST, "address", client_address or "*"])
            ok, got = lands_in(MATCH, FIRST)
            c.check("address equal to the client's address -> in the class", ok, got)
            script("06.userClasses_id_PATCH.sh", [FIRST, "address", "203.0.113.9"])
            ok, got = lands_in(MATCH, "VirtClass")
            c.check("address of another host -> VirtClass", ok, got)
            script("06.userClasses_id_PATCH.sh", [FIRST, "address", "*"])
            ok, got = lands_in(MATCH, FIRST)
            c.check("address * -> in the class again", ok, got)

            # -- two classes that fit: the lower order wins -------------------------------------------
            c.info("--- 02, 06 and 07: of two classes that fit, the lower order wins; a delete lets the other win")
            out = script("02.userClasses_POST.sh", [SECOND, MATCH, "true", "true"])
            tracked.add(SECOND)
            c.check("02 a second enabled class for the MATCH account is FIRST, the older one second",
                    wait_until(lambda: names_by_order() == [SECOND, FIRST, "VirtClass", "RealClass"]), names_by_order())
            ok, got = lands_in(MATCH, SECOND)
            c.check("the effect: the newer class (order 1) wins", ok, got)
            out = script("06.userClasses_id_PATCH.sh", [SECOND, "order", "2"])
            c.check("06 order 2 moves it behind the other one: the order of the others shifts",
                    wait_until(lambda: names_by_order() == [FIRST, SECOND, "VirtClass", "RealClass"]) and "is now '1'." in out, (names_by_order(), out[-200:]))
            ok, got = lands_in(MATCH, FIRST)
            c.check("the effect: the older class (now order 1) wins", ok, got)

            # a session that is open when its class goes
            in_first, session_id, held = login_class(MATCH, hold=True)
            open_clients.append(held)
            c.check("a session is open in %s" % FIRST, in_first == FIRST, in_first)
            # a template account that names the class, and one that names a class that does not exist
            template = admin.post("accounts", {"name": TEMPLATE, "type": "template", "homeFolder": "/home/" + TEMPLATE,
                                               "uid": str(UID_T), "gid": str(UID_T), "templateClass": FIRST})
            c.check("set up: a template account that names %s" % FIRST, template.status == 201, template.text[:200])
            accounts.append(TEMPLATE)
            nameless = admin.post("accounts", {"name": TEMPLATE_NO_CLASS, "type": "template", "homeFolder": "/home/" + TEMPLATE_NO_CLASS,
                                               "uid": str(UID_T + 1), "gid": str(UID_T + 1), "templateClass": "example_no_such_class"})
            c.check("a template account naming a class that does not exist is accepted too (201): the server never looks", nameless.status == 201, nameless.text[:200])
            accounts.append(TEMPLATE_NO_CLASS)

            # -- 07 ---------------------------------------------------------------------------------
            c.info("--- 07 deletes one class, never VirtClass or RealClass")
            for builtin in BUILTIN:
                out = script("07.userClasses_id_DELETE.sh", [builtin], expect_rc=2)
            c.check("07 VirtClass and RealClass are refused and still there", wait_until(lambda: all(find(b) is not None for b in BUILTIN)), names_by_order())
            script("07.userClasses_id_DELETE.sh", [], expect_rc=2)
            out = script("07.userClasses_id_DELETE.sh", [FIRST])
            c.check("07 deletes the class the MATCH account was in (even with a session in it and a template naming it): 204",
                    "HTTP 204" in out and wait_until(lambda: find(FIRST) is None), out[-300:])
            c.check("the classes after it moved up: the older class is gone, the newer one is first",
                    wait_until(lambda: names_by_order() == [SECOND, "VirtClass", "RealClass"]), names_by_order())
            ok, got = lands_in(MATCH, SECOND)
            c.check("the effect: the next login of the MATCH account is in the other class that fits", ok, got)
            c.check("the session that was open keeps its class's name in the list",
                    wait_until(lambda: any(s["id"] == session_id and s["userClass"] == FIRST for s in sessions())),
                    [s["userClass"] for s in sessions() if s["id"] == session_id])
            c.check("and the connection is still open (the client is still connected)", held.alive())
            held.close()
            read = admin.get("accounts/" + TEMPLATE, params={"type": "template", "fields": "templateClass"}).json()
            c.check("the template account still names the deleted class (the delete was not refused, nothing was changed)", read.get("templateClass") == FIRST, read)
            c.check("a templateClass is only readable with type=template (without it: 400 Field templateClass does not exist)",
                    admin.get("accounts/" + TEMPLATE, params={"fields": "templateClass"}).status == 400)
            script("07.userClasses_id_DELETE.sh", [FIRST], expect_rc=1, retry=False)
            script("07.userClasses_id_DELETE.sh", [SECOND])
            c.check("both of ours are deleted: the list is VirtClass and RealClass, in that order",
                    wait_until(lambda: names_by_order() == ["VirtClass", "RealClass"]), names_by_order())
            ok, got = lands_in(MATCH, "VirtClass")
            c.check("the effect: with no class of ours the MATCH account is in VirtClass", ok, got)

        LABEL[0] = ""
        PROTO = "SFTP"

        # -- the expression check, the raw API ----------------------------------------------------------
        c.info("--- the raw API: the expression is checked when it is saved")
        for text in ("1==1", "true && false", "!true", "user.name == \"bob\"", "nonsense("):
            refused = admin.post("userClasses", {"className": "example_expr", "userType": "*", "userName": MATCH, "group": "*", "address": "*", "expression": text})
            if refused.status == 201:
                tracked.add("example_expr")
                admin.delete("userClasses/" + find("example_expr")["id"])
            c.check("expression %s is refused: 400 'is not valid'" % text, refused.status == 400 and "is not valid" in refused.text, (refused.status, refused.text[:150]))
        for text in ("true and true", 'isset("a") ? true : false', "1 > 0"):
            made = admin.post("userClasses", {"className": "example_expr", "userType": "*", "userName": MATCH, "group": "*", "address": "*", "expression": text})
            tracked.add("example_expr")
            c.check("expression %s is accepted: 201" % text, made.status == 201, (made.status, made.text[:150]))
            if made.status == 201:
                admin.delete("userClasses/" + find("example_expr")["id"])
        longer = admin.post("userClasses", {"className": "example_expr", "userType": "*", "userName": MATCH, "group": "*", "address": "*", "expression": "x" * 1025})
        c.check("an expression of 1025 characters is 400", longer.status == 400, longer.text[:150])
        body = {"className": "example_expr", "userType": "virtual", "userName": MATCH, "group": "*", "address": "*"}
        for label, change, want in (("host instead of address", {"address": None, "host": "*"}, "Unsupported parameter - host"),
                                    ("userType in capitals", {"userType": "Real"}, "Valid userType values are"),
                                    ("a name with a space", {"className": "example expr"}, "contains whitespace"),
                                    ("an empty address", {"address": ""}, "address is empty")):
            sent = {k: v for k, v in dict(body, **change).items() if v is not None}
            refused = admin.post("userClasses", sent)
            c.check("POST with %s is 400 (%s)" % (label, want), refused.status == 400 and want in refused.text, (refused.status, refused.text[:200]))
        asked = admin.post("userClasses", dict(body, order=7))
        tracked.add("example_expr")
        c.check("`order` in a POST is ignored: the new class is first", asked.status == 201 and wait_until(lambda: names_by_order()[0] == "example_expr"), names_by_order())
        admin.delete("userClasses/" + find("example_expr")["id"])
        c.check("deleting it puts the order of VirtClass and RealClass back", wait_until(lambda: names_by_order() == ["VirtClass", "RealClass"]), names_by_order())
finally:
    for client in open_clients:
        try:
            client.close()
        except Exception:
            pass
    logins.cleanup()
    for k in classes():
        if k["className"] in tracked or k["className"].lower().startswith("example_"):
            admin.delete("userClasses/" + k["id"])
    for account in accounts:
        admin.delete("accounts/" + account)
    c.check("nothing is left behind: no class of ours, no account of ours",
            wait_until(lambda: not any(k["className"].lower().startswith("example_") for k in classes())
                       and not any(admin.exists("accounts/" + a) for a in accounts)))
    after = {k["id"]: k for k in classes()}
    c.check("the whole list of classes is as it was before: VirtClass and RealClass, their ids and their order",
            wait_until(lambda: {k["id"]: k for k in classes()} == saved), (sorted((k["order"], k["className"]) for k in after.values()),
                                                                            sorted((k["order"], k["className"]) for k in saved.values())))
    admin.logout()

sys.exit(c.done())
