#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified stUpdateAllRoutes.py
(example 1 only - see below) against every SIMPLE route on the server,
including a throwaway one built to match its hardcoded example condition,
and verifies the real, pre-existing routes are left alone while the
throwaway one is patched exactly as described.

This scans *every* SIMPLE route on the server, which sounds like the same
"server-wide blast radius" problem 21/22/23 and the still-uncovered
stUpdateAllSubscriptions.py have. It genuinely is not, confirmed directly
before writing this: the script's own example match conditions are narrow
enough that nothing pre-existing on this lab qualifies.

  - Example 1 (`updateFailureEmail`) only patches a route whose
    `failureEmailName` contains the exact literal `oldteam@example.com`.
    Confirmed directly: none of this lab's three real SIMPLE routes
    (`john-sftp-send-to-partner`, `mcp-test-simple`, `SimpleRoute`) have a
    `failureEmailName` set at all.
  - Example 2 (`updateStepFields`) only patches a step of type
    `CustomStepTracking` that also carries `customProperties.mHostName` or
    `.mPort`. Confirmed directly: `CustomStepTracking` is not a real,
    creatable step type on this server at all (`POST /routes` rejects it
    outright, "Route Step type is undefined") - it is illustrative filler
    in the example, not a type this API implements. This check runs a
    substituted copy with `updateStepFields` flipped to `False`, since
    there is no way to create a genuine, non-throwaway-but-still-safe
    positive case for it.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run stUpdateAllRoutes.py for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

c = st_client.Checker("stUpdateAllRoutes.py (example 1 only), run for real from "
                       "Admin/API 2.0/python/python3")

PY_TREE = runner.path("Admin", "API 2.0", "python")
SCRIPT = os.path.join(PY_TREE, "python3", "stUpdateAllRoutes.py")
ROUTE_NAME = "ZZTEST_stUpdateAllRoutes"
EMAIL_TO_REMOVE = "oldteam@example.com"
OTHER_EMAIL = "keepme@example.com"

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /routes PATCH; run this "
           "against a real server to exercise it")
    client.logout()
    sys.exit(c.done())

if client.exists("routes/" + ROUTE_NAME):
    c.info('a route named "%s" already exists on this server; skipping this '
           "check rather than reuse it." % ROUTE_NAME)
    client.logout()
    sys.exit(c.done())

real_simple_routes = [r for r in client.page("routes", params={"type": "SIMPLE"})
                     if r.get("name") != ROUTE_NAME]
original_by_id = {r["id"]: r.get("failureEmailName") for r in real_simple_routes}

route_id = None
try:
    response = client.post("routes", {
        "name": ROUTE_NAME, "type": "SIMPLE", "conditionType": "ALWAYS", "condition": "true",
        "failureEmailName": "%s,%s" % (EMAIL_TO_REMOVE, OTHER_EMAIL),
    })
    created = response.status == 201
    c.check('created a throwaway SIMPLE route "%s" matching the example condition' % ROUTE_NAME,
            created, response.text[:200])
    if not created:
        raise SystemExit(c.done())
    route_id = response.headers.get("Location", "").rstrip("/").rsplit("/", 1)[-1]

    with runner.real_credentials_python(PY_TREE, config):
        subs = {"    updateStepFields = True": "    updateStepFields = False",
               "    dryRun = True": "    dryRun = False"}
        with runner.substituted_copy(SCRIPT, subs) as copy:
            result = runner.run_python(copy)
            c.check("stUpdateAllRoutes.py runs without a shell level error "
                    "(dryRun False, updateStepFields False)", result.returncode == 0,
                    result.stderr.strip()[-300:] if result.returncode else "")
            c.check("it reports patching exactly one route",
                    "I patched:   1 of them" in result.stdout, result.stdout[-300:])

    after = client.get("routes/" + route_id).json() or {}
    c.check("the throwaway route's failureEmailName had the removed address stripped",
            after.get("failureEmailName") == OTHER_EMAIL, after.get("failureEmailName"))

    unaffected = all(client.get("routes/" + rid).json().get("failureEmailName") == original
                     for rid, original in original_by_id.items())
    c.check("every real, pre-existing SIMPLE route is unaffected", unaffected,
            {rid: client.get("routes/" + rid).json().get("failureEmailName")
             for rid in original_by_id})

finally:
    if route_id:
        client.delete("routes/" + route_id)
        c.check('the throwaway route "%s" was removed' % ROUTE_NAME,
                not client.exists("routes/" + route_id))
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own calls)"
       % client.calls)

sys.exit(c.done())
