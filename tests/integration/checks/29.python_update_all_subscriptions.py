#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified stUpdateAllSubscriptions.py
- with no type filter, its own documented default - against every real
subscription on the server, then restores every one of them to its exact
original state and verifies the restore.

This is the one script in this project explicitly approved to touch real,
pre-existing objects it does not own, rather than a disposable one it
creates. Confirmed directly while looking for a safe way around that: the
four fields this script patches only make sense on `Basic`/`AdvancedRouting`
subscriptions, and this lab's only subscriptions of those types already
belong to real accounts (`john`, `mcp-test-acme`) that this project did not
create - there is no type this script's own filter can select that both
matches its field shape and excludes them. Given an explicit, informed
decision to proceed anyway, this check captures every one of the four
fields on every real subscription before doing anything, runs the real
script, and restores every field to its exact original value afterward,
verifying the restore independently - the same discipline every other
check here already applies to daemons, servers and configuration options,
just applied to objects this project does not own instead of ones it does.

Confirmed directly while building this: two of the five real subscriptions
here are type `Basic`, which - unlike `AdvancedRouting` - has no
`postProcessingActions` object at all. The script's own patch sends a
`replace` on `/postProcessingActions/ppaOnSuccessInDoDelete` as the first
of four operations in one request; a `replace` on a field that does not
exist fails the whole PATCH (JSON Patch is all-or-nothing here, as every
other PATCH in this project already assumes), so those two are left
completely untouched by the script's own logic - not something this check
needs to restore, only confirm.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py -
and, given what it touches, should only ever be run with that explicit,
informed understanding, not as a routine part of "does everything still
pass".
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
    st_client.skip("read only run, pass --write to run stUpdateAllSubscriptions.py for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

c = st_client.Checker("stUpdateAllSubscriptions.py (no type filter - touches real "
                       "subscriptions, by explicit decision), run for real from "
                       "Admin/API 2.0/python/python3")

PY_TREE = runner.path("Admin", "API 2.0", "python")
SCRIPT = os.path.join(PY_TREE, "python3", "stUpdateAllSubscriptions.py")
FIELDS = "id,type,account,postProcessingActions,subscriptionEncryptMode,flowAttrsMergeMode,maxParallelSitPulls"

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /subscriptions PATCH; run "
           "this against a real server to exercise it")
    client.logout()
    sys.exit(c.done())


def snapshot():
    return {s["id"]: s for s in client.page("subscriptions", params={"fields": FIELDS})}


original = snapshot()
c.info("original subscriptions: %s" % original)

has_ppa = {sid: bool(s.get("postProcessingActions")) for sid, s in original.items()}


def restore_body(sub_id, before):
    ops = []
    if has_ppa[sub_id]:
        ops.append({"op": "replace", "path": "/postProcessingActions/ppaOnSuccessInDoDelete",
                   "value": before.get("postProcessingActions", {}).get("ppaOnSuccessInDoDelete")})
    for field in ("subscriptionEncryptMode", "flowAttrsMergeMode", "maxParallelSitPulls"):
        original_value = before.get(field)
        if original_value is None:
            ops.append({"op": "remove", "path": "/" + field})
        else:
            ops.append({"op": "replace", "path": "/" + field, "value": original_value})
    return ops


try:
    with runner.real_credentials_python(PY_TREE, config):
        subs = {"    dryRun = True": "    dryRun = False"}
        with runner.substituted_copy(SCRIPT, subs) as copy:
            result = runner.run_python(copy, timeout=90)
            c.check("stUpdateAllSubscriptions.py runs without a shell level error "
                    "(dryRun False)", result.returncode == 0,
                    result.stderr.strip()[-300:] if result.returncode else "")
            expected_patched = sum(1 for v in has_ppa.values() if v)
            c.check("it reports patching exactly the %d AdvancedRouting subscriptions "
                    "(the 2 Basic ones have no postProcessingActions to replace)"
                    % expected_patched,
                    ("I patched:   %d of them" % expected_patched) in result.stdout,
                    result.stdout[-300:])

    after = snapshot()
    for sub_id, before in original.items():
        now = after.get(sub_id, {})
        if has_ppa[sub_id]:
            c.check("subscription %s (%s/%s) got the real patch applied" %
                    (sub_id, now.get("account"), now.get("type")),
                    now.get("postProcessingActions", {}).get("ppaOnSuccessInDoDelete") is True
                    and str(now.get("subscriptionEncryptMode", "")).lower() == "default"
                    and now.get("flowAttrsMergeMode") == "preserve"
                    and str(now.get("maxParallelSitPulls")) == "10",
                    now)
        else:
            c.check("subscription %s (%s/%s), with no postProcessingActions, was left "
                    "completely untouched" % (sub_id, now.get("account"), now.get("type")),
                    now == before, (before, now))

finally:
    for sub_id, before in original.items():
        if has_ppa[sub_id]:
            client.patch("subscriptions/" + sub_id, restore_body(sub_id, before))

    final = snapshot()
    all_restored = True
    for sub_id, before in original.items():
        now = final.get(sub_id, {})
        if now != before:
            all_restored = False
        c.check("subscription %s (%s/%s) restored to its exact original state" %
                (sub_id, before.get("account"), before.get("type")),
                now == before, (before, now))
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own calls)"
       % client.calls)

sys.exit(c.done())
