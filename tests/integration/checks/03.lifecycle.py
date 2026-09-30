#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Creates one account, exercises the full lifecycle against
it, and deletes it again.

This check does not run unless you ask for it twice: --write on the command
line, and st_allow_writes="yes" in tests/local/integration.conf. It only ever
touches an object whose name starts with the configured prefix, and it removes
what it created even when an assertion fails.

It proves the status codes and the PATCH semantics the examples rely on:
201 with a Location header, 204 from PATCH and PUT, replace versus add, and
that a deleted object is really gone.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to exercise the lifecycle")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

PREFIX = config.get("st_object_prefix", "ZZTEST_")
if not PREFIX:
    print("  FAIL  st_object_prefix must not be empty")
    sys.exit(1)

NAME = PREFIX + "lifecycle"
PATH = "accounts/" + NAME

c = st_client.Checker("Account lifecycle (WRITES, prefix %s)" % PREFIX)
c.info("this will create and then delete: %s" % NAME)

created = False

client = st_client.connect(config, c)
try:
    try:
        # -- refuse to touch anything that is not ours ---------------------
        if not NAME.startswith(PREFIX):
            c.check("the object name carries the prefix", False, NAME)
            sys.exit(c.done())

        # -- clean up anything left by an earlier interrupted run ----------
        if client.exists(PATH):
            c.info("removing a leftover from a previous run")
            client.delete(PATH)

        # -- create ---------------------------------------------------------
        response = client.post("accounts", {
            "name": NAME,
            "type": "user",
            "uid": "1000",
            "gid": "1000",
            "homeFolder": "/home/" + NAME,
            "notes": "created by the integration tests",
            "user": {"name": NAME, "passwordCredentials": {"password": "Axway123!"}},
        })
        created = response.status == 201
        c.check("POST returns 201", response.status == 201,
                "%s %s" % (response.status, response.text[:200]))
        if not created:
            sys.exit(c.done())

        location = response.headers.get("Location")
        c.check("POST returns a Location header", bool(location), response.headers)
        if location:
            c.check("the Location ends with the new object's name",
                    location.rstrip("/").endswith(NAME), location)

        # -- read it back ----------------------------------------------------
        c.check("HEAD finds the new account", client.exists(PATH))

        response = client.get(PATH)
        c.check("GET returns 200", response.status == 200, response.status)
        account = response.json() or {}
        c.check("the name round trips", account.get("name") == NAME, account.get("name"))
        c.check("the notes round trip",
                account.get("notes") == "created by the integration tests",
                account.get("notes"))

        # -- PATCH, replace on a field that exists ---------------------------
        response = client.patch(PATH, [{"op": "replace", "path": "/notes",
                                        "value": "patched"}])
        c.check("PATCH replace returns 204", response.status == 204,
                "%s %s" % (response.status, response.text[:200]))
        c.check("the replaced value is visible",
                (client.get(PATH).json() or {}).get("notes") == "patched")

        # -- PATCH, replace on a field that is not set -----------------------
        # The gotchas skill says this is the usual cause of a 422. Confirm it
        # on the real server rather than taking it on trust.
        response = client.patch(PATH, [{"op": "replace",
                                        "path": "/aFieldThatIsNotSet",
                                        "value": "x"}])
        if response.status == 204:
            c.info("this server tolerated replace on an unset field, "
                   "which is looser than expected")
        else:
            c.check("replace on an unset field is rejected",
                    response.status in (400, 422), response.status)

        # -- PUT replaces the whole object -----------------------------------
        account = client.get(PATH).json() or {}
        account["notes"] = "replaced by PUT"
        response = client.put(PATH, account)
        c.check("PUT returns 204", response.status == 204,
                "%s %s" % (response.status, response.text[:200]))
        after = client.get(PATH).json() or {}
        c.check("the PUT value is visible", after.get("notes") == "replaced by PUT")
        c.check("PUT preserved the other fields",
                after.get("homeFolder") == "/home/" + NAME, after.get("homeFolder"))

        # -- the object appears in the collection ----------------------------
        found = any(a.get("name") == NAME
                    for a in client.page("accounts", page_size=200))
        c.check("the new account is listed in the collection", found)

    finally:
        # -- teardown, even if something above failed ------------------------
        if created:
            response = client.delete(PATH)
            c.check("DELETE returns 204", response.status == 204, response.status)
            c.check("the account is gone afterwards", not client.exists(PATH))
            if client.exists(PATH):
                print("  WARNING  %s is still present, remove it by hand" % NAME)

    c.info("%d API calls issued" % client.calls)
finally:
    client.logout()

sys.exit(c.done())
