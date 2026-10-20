# tests/local: your private workspace

`tests/local/` is where everything goes that must not reach the repository. Git ignores it. This folder,
`tests/local.example/`, is the committed starting point: **copy what you need, then edit the copy.**

```
mkdir -p tests/local
cp -n tests/local.example/* tests/local/      # -n: never overwrites a file you already have
```

`cp -n` says "not overwritten" (and may exit 1) for a file you already have: that is what `-n` is for. Do not use
`cp -r tests/local.example tests/local` when `tests/local` exists: it makes `tests/local/local.example`.

## What is here

| File | Copy it to | What it is |
| ---- | ---------- | ---------- |
| `integration.conf` | `tests/local/integration.conf` | The server the **online** checks talk to, and the safety switches. **This is the one that enables something**: without it `tests/online/run_online.sh` skips (it says so and exits 0). Edit `st_server`, `st_port`, `st_user`, `st_password`, then `st_confirm_lab="yes"` (your statement that the server is a lab, not production) and, for the checks that write, `st_allow_writes="yes"`. Every other setting is optional and explained in the file. |
| `blocked_terms.txt` | `tests/local/blocked_terms.txt` | A list of names (a customer, an internal host) that the hygiene check must never find in a tracked file. One regular expression per line. It lives in `tests/local` so the list itself never reaches the repository. Optional: with nothing in it only the built-in terms are checked. |

The values in `integration.conf` are placeholders (`st_confirm_lab="no"`), so a copy you have not edited cannot
reach any server. See [tests/online/README.md](../online/README.md) for what the checks do and how to run them.

## One more thing the online checks may need: a Python venv

Online checks 15 to 18 and 20 run the python examples, which import `requests`. The harness itself does not need it.
Create the venv once (it is a folder, not a file, so there is nothing to copy):

```
python3 -m venv tests/local/pyvenv
tests/local/pyvenv/bin/pip install requests
```

Those checks skip, with a message, when it is not there.

## Everything else you may keep here

- responses captured from a real server (`curl ... > tests/local/accounts.json`), which carry hostnames, account names,
  certificate subjects and business units
- the API descriptions fetched from a server: `tests/local/admin20-spec/`, `tests/local/enduser-spec/`
  (`.claude/skills/st-api-cover-resource/scripts/fetch_spec.sh` fills the first one)
- an exported `systemConfiguration.xml`
- logs and output from a run against a live server

`tests/local/harness_backups/` is written by the harness itself (a copy of a config it temporarily replaces, so that a
killed run cannot lose it). Leave it alone.

Nothing here is required: `tests/offline/run_all.sh` passes on a clean clone without any of it.

## Using a captured response as a fixture

The fake ST in `tests/offline/lib/fake_st.py` will serve any JSON you give it, so a real
response can drive the tests:

```python
import json, fake_st
routes = json.load(open("tests/local/real_routes.json"))["result"]
session = fake_st.FakeSession({"routes": routes})
```

That is the most realistic test available, because the shapes are real. Keep the file in `tests/local/`.
**Only move it to `tests/offline/fixtures/` after scrubbing every hostname, account name and identifier**:
fixtures are committed.

## Pointing a script at a real server

The example trees have their own settings file, `set_variables.local.sh` next to each example folder (copied from its
`set_variables.local.example.sh`; git ignores it). This folder is for the data you collect and for the test
configuration, not for the settings of the examples.
