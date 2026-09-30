# tests/local — your private workspace

Copy this directory to `tests/local`, which git ignores:

    cp -r tests/local.example tests/local

## integration.conf

The integration tests read `tests/local/integration.conf`, which names a real
server and the credentials for it:

    cp tests/integration/integration.conf.example tests/local/integration.conf

Without it the integration tests skip, so this is the one file here that
actually enables something. See tests/integration/README.md.

## Everything else

Put here anything that must not reach the repository:

- responses captured from a real server (`curl ... > tests/local/accounts.json`),
  which carry hostnames, account names, certificate subjects and business units
- a `config` or `set_variables.local.sh` pointing at a real system
- an exported `systemConfiguration.xml`
- logs and output from a run against a live server

Nothing here is required. `tests/run_all.sh` passes on a clean clone without it.

## Using a captured response as a fixture

The fake ST in `tests/lib/fake_st.py` will serve any JSON you give it, so a real
response can drive the tests:

```python
import json, fake_st
routes = json.load(open("tests/local/real_routes.json"))["result"]
session = fake_st.FakeSession({"routes": routes})
```

That is the most realistic test available, because the shapes are real. Keep the
file in `tests/local/`. **Only move it to `tests/fixtures/` after scrubbing every
hostname, account name and identifier** — fixtures are committed.

## Pointing a script at a real server

Configure the example trees as normal; those config files are already gitignored.
This directory is for the data you collect, not for the credentials themselves.
