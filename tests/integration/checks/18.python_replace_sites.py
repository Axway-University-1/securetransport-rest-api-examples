#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the actual, unmodified stReplaceSites.py in
Admin/API 2.0/python/python3 against every real SSH-protocol site on the
server, then restores each site's original keyExchangeAlgorithms and
verifies the restore.

This is not a disposable-object check like most others here. stReplaceSites.py
scans *every* SSH site with no name or prefix filter and overwrites the
keyExchangeAlgorithms of any that do not match a hardcoded "master" list -
confirmed directly, this server has real SSH sites that look like genuine
partner connections. There is no throwaway substitute the way
05.applications_scripts.py redirects at a different application: the only
way to exercise this script for real is against whatever real sites already
exist. This was deliberately excluded until explicitly requested with that
understood; see tests/integration/README.md.

Safety net: every site's full object is read and saved before the script
runs. After verifying the script's own change, every site is PUT back with
its saved object - the same "read the whole object, modify your copy, PUT it
back" pattern this repository's own gotchas skill already documents - and
the restore is verified against the saved copy.

Confirmed directly, and worth knowing before trusting a PUT round-trip on a
site: an already-encrypted password field (the "{AES128}..." form GET
returns) survives a full no-op PUT unchanged - the server recognises it as
already encrypted rather than re-encrypting it as new plaintext. A PUT does
NOT perfectly round-trip the object, though: a handful of FIPS-mode fields
(fipsCipherSuites, fipsAllowedMacs, fipsKeyExchangeAlgorithms, fipsPublicKeys)
and lastModifiedStartType/lastModifiedEndType come back populated with
server defaults afterward even when sent back exactly as GET returned them,
rather than staying empty/null. This check does not fight that: those fields
only matter when fipsMode is enabled (confirmed false on every site here) or
when the corresponding date value is set (confirmed null here), so it is an
inert, cosmetic side effect of PUT on this object type - not something
special to this script - and is not asserted on. keyExchangeAlgorithms and
password are asserted on, since those are what matters.

stReplaceSites.py is a dry run unless given --apply. This check runs it both ways:
without --apply nothing may change on any site (compared with the saved copy), with it
every site is replaced as described.

Needs tests/local/pyvenv - see 15.python_read_scripts.py's docstring.

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
    st_client.skip("read only run, pass --write to run the replace-sites script for real")

if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

if not runner.python_available():
    st_client.skip("no tests/local/pyvenv - see 15.python_read_scripts.py's docstring")

c = st_client.Checker("Python replace-sites, run for real against every SSH site on the server")

PY_TREE = runner.path("Admin", "API 2.0", "python")
PY_DIR = os.path.join(PY_TREE, "python3")
SCRIPT = os.path.join(PY_DIR, "stReplaceSites.py")

with open(SCRIPT) as f:
    match = re.search(r"masterKexAlg = '([^']*)'", f.read())
MASTER_KEX = match.group(1)

client = st_client.connect(config, c)

if st_client.is_mock(client):
    c.info("the bundled mock does not implement /sites; run this against a "
           "real server to exercise it")
    client.logout()
    sys.exit(c.done())

sites = list(client.page("sites", params={"protocol": "ssh"}))
c.info("%d real SSH site(s) on this server - all of them are in scope, by design "
       "of the script this check runs" % len(sites))
backups = {s["id"]: client.get("sites/" + s["id"]).json() for s in sites}

try:
    with runner.real_credentials_python(PY_TREE, config):
        result = runner.run_python(SCRIPT, timeout=120)
        c.check("stReplaceSites.py without --apply is a dry run: exit 0, and says it changed nothing",
                result.returncode == 0 and "DRY RUN" in result.stdout and "Successfully" not in result.stdout,
                (result.stdout + result.stderr)[-300:])
        unchanged = all((client.get("sites/" + i).json() or {}).get("keyExchangeAlgorithms") == o.get("keyExchangeAlgorithms")
                        for i, o in backups.items())
        c.check("and no site changed", unchanged)

        result = runner.run_python(SCRIPT, ["--apply"], timeout=120)
        c.check("stReplaceSites.py --apply runs without a shell level error",
                result.returncode == 0,
                (result.stdout + result.stderr).strip()[-300:] if result.returncode else "")

    for site_id, original in backups.items():
        name = original.get("name")
        after = client.get("sites/" + site_id).json() or {}
        if original.get("keyExchangeAlgorithms") == MASTER_KEX:
            c.check('"%s" already matched the master list and is unchanged' % name,
                    after.get("keyExchangeAlgorithms") == MASTER_KEX)
        else:
            c.check('"%s" was updated to the master key exchange list' % name,
                    after.get("keyExchangeAlgorithms") == MASTER_KEX,
                    after.get("keyExchangeAlgorithms"))
        c.check('"%s" password field is unaffected' % name,
                after.get("password") == original.get("password"))

finally:
    for site_id, original in backups.items():
        name = original.get("name")
        response = client.put("sites/" + site_id, original)
        c.check('"%s" restored: PUT returns 204' % name, response.status == 204,
                response.status)
        restored = client.get("sites/" + site_id).json() or {}
        c.check('"%s" keyExchangeAlgorithms matches its original value' % name,
                restored.get("keyExchangeAlgorithms") == original.get("keyExchangeAlgorithms"),
                restored.get("keyExchangeAlgorithms"))
        c.check('"%s" password matches its original value' % name,
                restored.get("password") == original.get("password"))
    client.logout()

c.info("%d API calls issued by the verification client (not counting the script's own calls)"
       % client.calls)

sys.exit(c.done())
