#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs a count-trimmed copy of the real, unmodified
08.RouteTemplates/02.routes_POST.sh, then the real, unmodified
09.CompositeRoutes/02.routes_POST.sh, against a configured server.

08.RouteTemplates/02.routes_POST.sh hardcodes an array of 163 route template
names and POSTs one for each - a large number of near-identical objects that
this project's own README already warns slows the admin UI down. Every
iteration does the exact same POST with only the name different, so a
trimmed array exercises the same loop mechanics just as validly - the same
reasoning already applied to stBuildTestAccounts.py (100 accounts trimmed to
3). This check computes the substitution from the real file's own current
TEMPLATE_NAMES array at run time (rather than hardcoding a second copy of a
163-line array here to match against), and trims it to three names:

  - "RouteFromAccountant" - kept, because 09.CompositeRoutes/02.routes_POST.sh
    specifically depends on a route template with this exact name existing.
    Running the trimmed 08 script first is what makes it possible to run the
    real, unmodified 09 script afterward at all.
  - Two more of the original 163 names, kept as-is, so the loop is still
    exercised more than once.

Every other name in the original array is left out of the substituted copy
entirely - not created, not touched.

09.CompositeRoutes/02.routes_POST.sh needs no substitution at all: it already
depends on "RouteFromAccountant" and the account "john" (confirmed to
exist), and creates three more objects by their real, literal names -
"CompositeRoute_WithoutExtension", "SimpleRouteName" and
"CompositeRoute_WithExtension" - not ZZTEST_ prefixed, the same treatment
04.accounts_scripts.py and 05.applications_scripts.py already give the
literal names their own folders' scripts use.

Refuses to run at all if any of the five objects these two scripts touch by
name already exist on the server, rather than risk colliding with something
already meaningful there.

Needs --write and st_allow_writes="yes", same as 04.accounts_scripts.py.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")

if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the RouteTemplates/CompositeRoutes scripts for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("RouteTemplates (trimmed) and CompositeRoutes, run for real from "
                       "Admin/API 2.0/bash/08.RouteTemplates and 09.CompositeRoutes")

BASH_TREE = runner.path("Admin", "API 2.0", "bash")
RT_SCRIPT = os.path.join(BASH_TREE, "08.RouteTemplates", "02.routes_POST.sh")
RT_DELETE_SCRIPT = os.path.join(BASH_TREE, "08.RouteTemplates", "03.routes_DELETE_all.sh")
CR_SCRIPT = os.path.join(BASH_TREE, "09.CompositeRoutes", "02.routes_POST.sh")

TEMPLATE_NAMES = ["RouteFromAccountant", "RouteFromEngineer", "RouteFromGovernment"]
COMPOSITE_NAMES = ["CompositeRoute_WithoutExtension", "SimpleRouteName", "CompositeRoute_WithExtension"]

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /routes; run this against a "
           "real server to exercise it")
    client.logout()
    sys.exit(c.done())

pre_existing = [n for n in (TEMPLATE_NAMES + COMPOSITE_NAMES)
               if (client.get("routes", params={"name": n}).json() or {}).get("result")]
if pre_existing:
    c.check("none of %s already exist on this server" % (TEMPLATE_NAMES + COMPOSITE_NAMES),
            False, pre_existing)
    c.info("refusing to run: it would collide with something already there. "
           "Remove %s by hand, or point this at a cleaner lab." % pre_existing)
    client.logout()
    sys.exit(c.done())
c.check("none of %s already exist on this server" % (TEMPLATE_NAMES + COMPOSITE_NAMES), True)

with open(RT_SCRIPT) as f:
    rt_source = f.read()
match = re.search(r"declare -a TEMPLATE_NAMES=\(.*?\n\)", rt_source, re.S)
if not match:
    c.check("found the TEMPLATE_NAMES array in 02.routes_POST.sh to trim it", False)
    client.logout()
    sys.exit(c.done())
c.check("found the TEMPLATE_NAMES array in 02.routes_POST.sh to trim it", True)

trimmed_array = "declare -a TEMPLATE_NAMES=(\n        %s\n)" % " ".join(
    '"%s"' % n for n in TEMPLATE_NAMES)
subs = {match.group(0): trimmed_array}

created_templates = False
created_composites = False

try:
    with runner.real_credentials(BASH_TREE, config):
        with runner.substituted_copy(RT_SCRIPT, subs) as copy:
            result = runner.run(copy, timeout=60)
            c.check("08.RouteTemplates/02.routes_POST.sh runs without a shell level error "
                    "(name/count-trimmed copy, 3 of 163)", result.returncode == 0,
                    result.stderr.strip()[-300:] if result.returncode else "")

        created_templates = True
        for n in TEMPLATE_NAMES:
            c.check("route template %s exists after the trimmed script" % n,
                    bool((client.get("routes", params={"name": n}).json() or {}).get("result")))

        result = runner.run(CR_SCRIPT, timeout=60)
        c.check("09.CompositeRoutes/02.routes_POST.sh runs without a shell level error",
                result.returncode == 0,
                result.stderr.strip()[-300:] if result.returncode else "")

        created_composites = True
        for n in COMPOSITE_NAMES:
            c.check("%s exists after 09.CompositeRoutes/02.routes_POST.sh" % n,
                    bool((client.get("routes", params={"name": n}).json() or {}).get("result")))

        # The composite routes inherit RouteFromAccountant, which cannot be deleted while they exist: remove
        # them through the API, then run the cleanup script of the templates (a trimmed copy, the same 3 names)
        for n in COMPOSITE_NAMES:
            for item in (client.get("routes", params={"name": n, "fields": "id"}).json() or {}).get("result", []):
                client.delete("routes/" + item["id"])
        with open(RT_DELETE_SCRIPT) as f:
            delete_match = re.search(r"declare -a TEMPLATE_NAMES=\(.*?\n\)", f.read(), re.S)
        c.check("found the TEMPLATE_NAMES array in 03.routes_DELETE_all.sh to trim it", bool(delete_match))
        if delete_match:
            with runner.substituted_copy(RT_DELETE_SCRIPT, {delete_match.group(0): trimmed_array}) as copy:
                result = runner.run(copy, timeout=60)
            c.check("08.RouteTemplates/03.routes_DELETE_all.sh runs without a shell level error "
                    "(name/count-trimmed copy, 3 of 163)", result.returncode == 0,
                    (result.stdout + result.stderr).strip()[-300:] if result.returncode else "")
            for n in TEMPLATE_NAMES:
                c.check("route template %s is gone after the delete script" % n,
                        not (client.get("routes", params={"name": n}).json() or {}).get("result"))

finally:
    for n in (COMPOSITE_NAMES if created_composites else []) + \
             (TEMPLATE_NAMES if created_templates else []):
        result = client.get("routes", params={"name": n, "fields": "id"})
        for item in (result.json() or {}).get("result", []):
            client.delete("routes/" + item["id"])
    still_there = [n for n in (TEMPLATE_NAMES + COMPOSITE_NAMES)
                  if (client.get("routes", params={"name": n}).json() or {}).get("result")]
    c.check("all created routes were removed", not still_there, still_there)
    client.logout()

c.info("%d API calls issued by the verification client (not counting the scripts' own curl calls)"
       % client.calls)

sys.exit(c.done())
