#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified stUpdateRouteWithPut.py in
Admin/API 2.0/python/python3, in its default 'insert' mode, against a
throwaway route this check creates - reads the route, inserts one step at
offset 0, PUTs the whole object back - then verifies the step landed and
deletes the route.

The script's own `mode` and `dryRun` are set in its configuration section,
not on the command line - dryRun defaults to True, so this check runs a
substituted copy with dryRun flipped to False, the same way
15.python_read_scripts.py substitutes stConfigScan.py's hardcoded baseline
path. 'insert' (the default mode) is the only one of the three modes this
check exercises: 'link' and 'subscription' both need a second, already
meaningful real object (an existing simple route or subscription) rather
than a disposable one - out of scope here, in the same spirit as
16.python_build_delete_accounts.py trimming stBuildTestAccounts.py's count
rather than building all 100 real accounts.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run stUpdateRouteWithPut.py for real")

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

c = st_client.Checker("stUpdateRouteWithPut.py (insert mode), run for real from "
                       "Admin/API 2.0/python/python3")

PY_TREE = runner.path("Admin", "API 2.0", "python")
SCRIPT = os.path.join(PY_TREE, "python3", "stUpdateRouteWithPut.py")
ROUTE_NAME = "ZZTEST_stUpdateRouteWithPut"

client = harness.connect(config, c, mock=("the bundled mock does not implement /routes; run this against a "
                                          "real server to exercise it"))

if client.exists("routes/" + ROUTE_NAME):
    c.info('a route named "%s" already exists on this server; skipping this '
           "check rather than reuse it. Delete it if it is leftover from a "
           "previous failed run." % ROUTE_NAME)
    client.logout()
    sys.exit(c.done())

route_id = None
try:
    response = client.post("routes", {"name": ROUTE_NAME, "type": "SIMPLE",
                                      "conditionType": "ALWAYS", "condition": "true"})
    created = response.status == 201
    c.check('created a throwaway SIMPLE route "%s"' % ROUTE_NAME, created, response.text[:200])
    if not created:
        raise SystemExit(c.done())
    route_id = response.headers.get("Location", "").rstrip("/").rsplit("/", 1)[-1]
    c.check("the Location header named the new route's id", bool(route_id),
            response.headers.get("Location"))

    before = client.get("routes/" + route_id).json() or {}
    c.check("the route starts with no steps", before.get("steps") == [], before.get("steps"))

    with runner.real_credentials_python(PY_TREE, config):
        subs = {"    dryRun = True": "    dryRun = False"}
        with runner.substituted_copy(SCRIPT, subs) as copy:
            result = runner.run_python(copy, [route_id])
            c.check("stUpdateRouteWithPut.py runs without a shell level error "
                    "(dryRun flipped to False)", result.returncode == 0,
                    result.stderr.strip()[-300:] if result.returncode else "")
            c.check("its own output confirms it actually wrote, not a dry run",
                    "Successfully updated route" in result.stdout, result.stdout[-300:])

    after = client.get("routes/" + route_id).json() or {}
    after_steps = after.get("steps") or []
    c.check("the route now has exactly one step", len(after_steps) == 1, after_steps)
    c.check("the inserted step is the EncodingConversion step the script's own "
            "configuration section defines",
            bool(after_steps) and after_steps[0].get("type") == "EncodingConversion",
            after_steps)

finally:
    if route_id:
        client.delete("routes/" + route_id)
        c.check('the throwaway route "%s" was removed' % ROUTE_NAME,
                not client.exists("routes/" + route_id))
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own calls)"
       % client.calls)

sys.exit(c.done())
