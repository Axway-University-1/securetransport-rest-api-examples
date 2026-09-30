#!/usr/bin/env python3
"""
Read only. Checks the API behaviours the examples depend on, against the real
server: paging, field selection, HEAD as an existence test, and what a missing
object returns.

These are the assumptions baked into every example in this repository. If a
release changes one of them, this is what tells you.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

c = st_client.Checker("API behaviours the examples rely on (read only)")

client = st_client.connect(config, c)
try:

    # -- a collection responds with the documented envelope ----------------
    response = client.get("accounts", params={"limit": 1})
    c.check("GET /accounts returns 200", response.status == 200, response.status)
    payload = response.json() or {}
    c.check("the response has a result list", isinstance(payload.get("result"), list))
    c.check("the response has a resultSet with returnCount",
            "returnCount" in (payload.get("resultSet") or {}),
            payload.get("resultSet"))

    # -- paging -------------------------------------------------------------
    # Ask for two small pages and confirm they do not overlap. This is the
    # contract every bulk example in the repository depends on.
    first = client.get("accounts", params={"offset": 0, "limit": 2}).json() or {}
    second = client.get("accounts", params={"offset": 2, "limit": 2}).json() or {}
    names_first = [a.get("name") for a in first.get("result", [])]
    names_second = [a.get("name") for a in second.get("result", [])]

    if len(names_first) < 2:
        c.info("fewer than 4 accounts on this server, so paging is not exercised")
    else:
        c.check("a second page returns different objects",
                not (set(names_first) & set(names_second)),
                "%s overlaps %s" % (names_first, names_second))

    # Walking the collection must terminate and not repeat itself
    walked = list(client.page("accounts", page_size=50, max_objects=500))
    unique = {a.get("name") for a in walked}
    c.check("walking the collection yields no duplicates",
            len(walked) == len(unique), "%d objects, %d unique" % (len(walked), len(unique)))
    c.info("%d accounts visible to this user" % len(walked))

    if not walked:
        c.info("no accounts to inspect, skipping the per object checks")
        sys.exit(c.done())

    sample = walked[0]["name"]

    # -- field selection ----------------------------------------------------
    response = client.get("accounts", params={"limit": 1, "fields": "name"})
    item = ((response.json() or {}).get("result") or [{}])[0]
    c.check("fields=name returns the name", "name" in item, item)
    c.check("the type comes back even though it was not asked for",
            "type" in item, sorted(item))
    c.check("fields really narrows the response",
            "homeFolder" not in item, sorted(item))

    # -- HEAD as an existence check ----------------------------------------
    c.check("HEAD on an account that exists returns 200",
            client.head("accounts/" + sample).status == 200)
    missing = "definitely_not_a_real_account_zz99"
    c.check("HEAD on an account that does not exist returns 404",
            client.head("accounts/" + missing).status == 404,
            client.head("accounts/" + missing).status)
    c.check("the exists helper agrees", client.exists("accounts/" + sample)
            and not client.exists("accounts/" + missing))

    # -- GET of a missing object -------------------------------------------
    c.check("GET of a missing account returns 404",
            client.get("accounts/" + missing).status == 404)

    # -- a type specific field needs the type ------------------------------
    # Documented in the gotchas skill: asking for addressBookSettings without
    # type=user gives you nothing back.
    without = client.get("accounts/" + sample,
                         params={"fields": "addressBookSettings"}).json() or {}
    with_type = client.get("accounts/" + sample,
                           params={"type": "user",
                                   "fields": "addressBookSettings"}).json() or {}
    if "addressBookSettings" in with_type:
        c.check("a type specific field needs type= to be returned",
                "addressBookSettings" not in without,
                "returned without type= as well")
    else:
        c.info("this account has no addressBookSettings, so the type rule "
               "could not be exercised")

    c.info("%d API calls issued" % client.calls)
finally:
    client.logout()

sys.exit(c.done())
