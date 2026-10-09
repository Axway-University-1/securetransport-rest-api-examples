#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 25.LdapDomains examples:

1. Add, list and filter, check, read, replace, change and delete throwaway LDAP
   domains, a name with a space among them, and every argument each example
   refuses. A PUT is checked to keep the bind password's ciphertext and to leave
   the name alone.

2. 08.ldapDomains_name_operations_POST_testConnection.sh against a "directory"
   on this machine: a TcpSink (tests/integration/lib/dummy_servers.py). The test
   only opens a connection, so that is enough. A domain gets two servers, one
   with the sink behind it and one with nothing listening; the example, given each
   server's number, says "Successful Connection." for the first (and the sink
   sees the server connect) and "Connection failed." for the second, and then
   for the first as well once the sink is gone.

An LDAP domain only authenticates users when the server's login settings turn
LDAP on, which is a server-wide change this check never makes.

Part 2 needs st_callback_host in integration.conf: this machine's address as the
server sees it (see integration.conf.example); without it only part 1 runs.
Needs --write and st_allow_writes="yes". Refuses to start when its example_ldap*
domains exist, and removes everything in a finally block.
"""
import os
import socket
import sys
from urllib.parse import quote

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402
import dummy_servers  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the LDAP domain examples for real")

c = st_client.Checker("LDAP domains, run for real from Admin/API 2.0/bash/25.LdapDomains")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "25.LdapDomains")
NAME, SPACED, CONNECTION = "example_ldap", "example ldap space", "example_ldap_conn"
BIND_PASSWORD = "Synthetic-Bind-1"
CALLBACK = config.get("st_callback_host", "")


def script(name, args=None, expect_rc=0):
    return harness.run_script(c, FOLDER, name, args, expect_rc, timeout=90, env={"LDAP_BIND_PASSWORD": BIND_PASSWORD})


def domain(name):
    response = admin.get("ldapDomains/" + quote(name, safe=""))
    return response.json() if response.status == 200 else None


def listening(port):
    """True when something on this machine accepts a connection on `port`."""
    try:
        socket.create_connection(("127.0.0.1", port), timeout=1).close()
        return True
    except OSError:
        return False


def free_port():
    with socket.socket() as s:
        s.bind(("0.0.0.0", 0))
        return s.getsockname()[1]


admin = harness.connect(config, c, mock="the bundled mock does not implement /ldapDomains")
if any(domain(n) for n in (NAME, SPACED, CONNECTION)):
    c.check("no example_ldap* domain exists yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

sink = None
try:
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        # ---- part 1: the examples
        out = script("02.ldapDomains_POST.sh")
        made = domain(NAME)
        c.check("02 added example_ldap, with the ST server as its directory, port 389",
                made and (made["ldapServers"][0]["host"], made["ldapServers"][0]["port"]) == (config["st_server"], 389), made)
        c.check("02 printed the domain's id, which is not its name", made and ("Its id: %s" % made["id"]) in out, out[-200:])
        c.check("02 the bind password reads back encrypted, never as sent",
                made and made["bindDnPassword"].startswith("{AES128}") and BIND_PASSWORD not in made["bindDnPassword"], made and made["bindDnPassword"])
        script("02.ldapDomains_POST.sh", [SPACED, "10.1.2.3", "1389"])
        c.check("02 a name with a space, its own host and port",
                (domain(SPACED) or {}).get("ldapServers", [{}])[0].get("host") == "10.1.2.3" and domain(SPACED)["ldapServers"][0]["port"] == 1389)
        script("02.ldapDomains_POST.sh", expect_rc=1)
        out = script("02.ldapDomains_POST.sh", ["example_ldap_nohost", "no.such.host.invalid"], expect_rc=1)
        c.check("02 a host the server cannot resolve is refused with its reason", "Invalid server host" in out and not domain("example_ldap_nohost"), out[-200:])
        total = admin.get("ldapDomains").json()["resultSet"]["totalCount"]
        for args in (["x", "h", "70000"], ["x", "h", "port"], [" "]):
            script("02.ldapDomains_POST.sh", args, expect_rc=2)
        c.check("02 a bad port or a blank name sent nothing", admin.get("ldapDomains").json()["resultSet"]["totalCount"] == total)

        out = script("01.ldapDomains_GET.sh", [NAME, "3"])
        c.check("01 lists the domains, with servers, base DN and default", "  %s  %s:389  ou=People,dc=example,dc=com  -" % (NAME, config["st_server"]) in out, out[-500:])
        c.check("01 one by its exact name", "The one named %s:\n  %s  " % (NAME, NAME) in out, out[-500:])
        c.check("01 and by protocol version", "Only the ones using LDAP version 3:\n" in out and out.split("version 3:")[-1].count("  %s  " % NAME) == 1, out[-300:])
        script("01.ldapDomains_GET.sh", ["", "4"], expect_rc=2)

        script("03.ldapDomains_name_HEAD.sh")
        script("03.ldapDomains_name_HEAD.sh", [SPACED])
        script("03.ldapDomains_name_HEAD.sh", ["example_ldap_nope"], expect_rc=1)
        out = script("04.ldapDomains_name_GET.sh", [SPACED])
        c.check("04 reads the domain with a space in its name, and each server's id",
                "  %s: LDAP version 3, not the default" % SPACED in out and "  server 1: 10.1.2.3:1389, id " in out, out[-500:])

        before = domain(NAME)
        script("05.ldapDomains_name_PUT.sh", [NAME, "replaced by the check"])
        after = domain(NAME)
        c.check("05 PUT changed the description and kept the name and the bind password's ciphertext",
                after and (after["description"], after["name"], after["bindDnPassword"]) == ("replaced by the check", NAME, before["bindDnPassword"]), after)
        script("05.ldapDomains_name_PUT.sh", ["example_ldap_nope"], expect_rc=1)
        script("06.ldapDomains_name_PATCH.sh", [NAME, "patched by the check", "390"])
        after = domain(NAME)
        c.check("06 PATCH changed the description and the first server's port",
                after and (after["description"], after["ldapServers"][0]["port"]) == ("patched by the check", 390), after)
        script("06.ldapDomains_name_PATCH.sh", [NAME, "x", "70000"], expect_rc=2)
        script("06.ldapDomains_name_PATCH.sh", ["example_ldap_nope"], expect_rc=1)
        script("08.ldapDomains_name_operations_POST_testConnection.sh", [NAME, "2"], expect_rc=1)
        script("08.ldapDomains_name_operations_POST_testConnection.sh", [NAME, "0"], expect_rc=2)

        script("07.ldapDomains_name_DELETE.sh")
        c.check("07 deleted example_ldap", domain(NAME) is None)
        script("07.ldapDomains_name_DELETE.sh", expect_rc=1)
        script("07.ldapDomains_name_DELETE.sh", [SPACED])
        c.check("07 deleted the domain with a space in its name", domain(SPACED) is None)

        # ---- part 2: the connection test, against a TcpSink
        if not CALLBACK:
            c.info("st_callback_host is not set: the connection test (part 2) is skipped")
        else:
            sink = dummy_servers.TcpSink()
            sink.__enter__()
            dead = free_port()
            script("02.ldapDomains_POST.sh", [CONNECTION, CALLBACK, str(sink.port)])
            patched = admin.patch("ldapDomains/" + CONNECTION, [{"op": "add", "path": "/ldapServers/-", "value": {"host": CALLBACK, "port": dead}}])
            c.check("set up: a second server, with nothing listening behind it", patched.status == 204, patched.text[:200])
            servers = (domain(CONNECTION) or {}).get("ldapServers", [])
            number = {s["port"]: i + 1 for i, s in enumerate(servers)}
            c.check("set up: the domain has the two servers", set(number) == {sink.port, dead}, servers)

            sink_port = sink.port
            seen = len(sink.connections)
            out = script("08.ldapDomains_name_operations_POST_testConnection.sh", [CONNECTION, str(number[sink_port])])
            c.check("08 the server with the sink behind it: Successful Connection.", "Successful Connection." in out, out[-200:])
            harness.wait_until(lambda: len(sink.connections) > seen, 5, 0.25)
            c.check("08 and the sink saw ST connect, and nothing was sent",
                    len(sink.connections) > seen and all(x["data"] == b"" for x in sink.connections[seen:]),
                    [(x["client"], x["data"]) for x in sink.connections[seen:]])
            out = script("08.ldapDomains_name_operations_POST_testConnection.sh", [CONNECTION, str(number[dead])], expect_rc=1)
            c.check("08 the server with nothing listening: Connection failed., exit 1", "Connection failed." in out, out[-200:])
            sink.__exit__(None, None, None)
            sink = None
            c.check("set up: nothing listens on the sink's port any more",
                    harness.wait_until(lambda: not listening(sink_port), 5, 0.25), sink_port)
            out = script("08.ldapDomains_name_operations_POST_testConnection.sh", [CONNECTION, str(number[sink_port])], expect_rc=1)
            c.check("08 once the sink is gone, the first server fails too", "Connection failed." in out, out[-200:])
finally:
    if sink is not None:
        sink.__exit__(None, None, None)
    for name in (NAME, SPACED, CONNECTION, "example_ldap_nohost"):
        admin.delete("ldapDomains/" + quote(name, safe=""))
    c.check("nothing is left behind", not any(domain(n) for n in (NAME, SPACED, CONNECTION, "example_ldap_nohost")))
    admin.logout()

sys.exit(c.done())
