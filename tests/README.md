# Tests

Checks that keep the examples in this repository correct. **Everything in the
Quick Start runs offline**: no SecureTransport server, no credentials, no
network.

## Quick Start

You need `bash`, `python3` and `jq`. On macOS: `brew install jq`. On Debian or
Ubuntu: `sudo apt install jq`.

**1. Run the tests** (about 5 seconds), from the repository root:

```
./tests/run_all.sh
```

**2. Read the result.** A good run ends with:

```
# ALL CHECKS PASSED  (5)
```

If something fails, scroll up. Each line starts with `PASS` or `FAIL`, and a
`FAIL` line says what it found. The name of the check that failed is printed
again at the very end.

**3. Run just one check** by giving part of its name:

```
./tests/run_all.sh hygiene
```

**4. Changed or added a script?** Add a test for it in the same change, then run
step 1 again. See [Adding a check](#adding-a-check).

That is all you need. Everything below is reference.

### Want to try it against a server?

You don't need one to try. The mock is a fake SecureTransport that ships with the
repository:

```
tests/integration/run_integration.sh --mock
```

Expect `6 passed, 22 skipped, 1 failed`. The one failure is
`12.myself_and_version_scripts` and is expected against the mock. The mock
enforces a `Referer` header on calls that don't send one, and the run says
"expect failures" before it starts.

To run against your own lab server, see [Against a real
server](#against-a-real-server).

---

## Full reference

### What is checked

| Check | What it catches |
| ----- | --------------- |
| `checks/check_hygiene.sh` | A credential, hostname, IP or customer name committed by accident. Naming that drifts from the convention. A shell file that does not parse. A bash example with no bat twin. |
| `checks/check_docs_match_repo.py` | Documentation that no longer matches the repository: README coverage tables whose counts differ from the directories, and `.claude` skills that describe a layout, file or variable that no longer exists. |
| `checks/test_bash_payloads.sh` | A curl example emitting malformed JSON, or an unexpanded `${VARIABLE}`, by running it against a stub `curl` that prints the payload instead of sending it. |
| `checks/test_python_logic.py` | The python examples doing the wrong thing, by running them against a fake ST that serves paged collections and records what they would write. |
| `checks/test_utils_xml.sh` | The XML helper scripts in `python/utils` (configuration compare and conversion). |
| `checks/test_feature_version_check.sh` | The version check at the start of every `Features/` example: it must run the example on a server at or after the introducing version, skip it on an older one, and stop with an error when the version cannot be read. Also fails if a feature example has no version check. |
| `checks/test_feature_trigger_route_pull.sh` | The `Features/trigger-route-after-completed-pull` examples: the JSON they send is valid (even with awkward characters in the password), the sites use the right folders and port, the push folder is never the subscription folder, an old server gets nothing sent, and a missing password stops them before any call. |
| `checks/test_feature_billable_transfers.sh` | The `Features/audit-billable-transfers` examples: each scenario's site, route and subscription bodies (including the Compress/Decompress steps and the two-backslash trigger condition), the archives built and uploaded are real zips, the billable report's per-day date math and query, `00.run_all.sh`'s step ordering and its stop-on-first-failure, and `99.cleanup_DELETE.sh` finding everything by name without touching another account's objects. |
| `checks/test_feature_bat_twins.py` | A `Features/` `.bat` file drifting out of step with its `.sh` twin: every API field name and every feature's own settings must appear in both, since the `.bat` files cannot be run in this repository to check directly. |

The payload and python checks are the interesting ones. They exercise the real
scripts without a server, which is how the silent JSON corruption described in
`.claude/skills/st-api-gotchas/SKILL.md` was found.

### Layout

```
tests/
    run_all.sh          runs everything in checks/
    lib/                the stubs: a fake curl, a fake ST API
    fixtures/           small synthetic inputs. No real data, ever.
    checks/             the checks themselves
    integration/        opt-in checks against a real server. See its README.
    local/              YOUR data. Git ignores this. See below.
    output/             run artifacts. Git ignores this.
```

### Adding a check

Every new script and every change needs a test in the same change.

1. Put an executable script in `checks/`. `run_all.sh` picks up anything named
   `check_*` or `test_*`, in bash or python, and treats exit code 0 as a pass.
2. Extend an existing check when one fits:
   - a bash example: `test_bash_payloads.sh`
   - a python example: `test_python_logic.py`
   - an XML helper: `test_utils_xml.sh`
3. Use synthetic inputs from `fixtures/`.
4. Keep it offline and fast. The point is that people actually run it.
5. For a bug fix, write the test that reproduces the bug first, and confirm it
   fails before you fix it.

The same suite runs on GitHub for every push and pull request
(`.github/workflows/tests.yml`).

### Against a real server

The checks above never touch a server. A separate, opt-in layer does:

```
tests/integration/run_integration.sh --mock     try it with no server at all
tests/integration/run_integration.sh            read only, against your server
tests/integration/run_integration.sh --write    also create and delete an account
```

It proves the server still behaves the way the examples assume: the CSRF
handshake, paging, status codes, PATCH semantics. It needs a config in
`tests/local/`, refuses to run unless that config states the server is a lab
system, and needs a second explicit yes before it writes anything. See
[integration/README.md](integration/README.md) for setup.

### tests/local: the part git ignores

`tests/local/` and `tests/output/` are excluded from git, so put anything here
that must not reach the repository:

- responses captured from a real server, which carry hostnames, account names,
  certificate subjects and business unit names
- a `config` or `set_variables.local.sh` pointing at a real system
- exported `systemConfiguration.xml` files
- logs and output from a run against a live server

Nothing in `tests/local/` is needed for `run_all.sh` to pass. It is a private
workspace, not a dependency.

`local.example/` shows the shape and is committed. Copy it:

```
cp -r tests/local.example tests/local
```

**Before you put a captured response in `fixtures/` instead, scrub it.** Fixtures
are committed. If you are unsure, it belongs in `local/`.

### Troubleshooting

| Symptom | Likely cause |
| ------- | ------------ |
| `jq: command not found` | Install `jq` (see Quick Start). |
| `Permission denied` on `run_all.sh` | `chmod +x tests/run_all.sh` |
| A check named `hygiene` fails | It found something that looks like a credential, hostname or IP. Read the `FAIL` line, then replace it with a placeholder such as `<SERVER>`. |
| A check named `docs_match_repo` fails | You added or removed a script and the README count or a `.claude` skill is now out of date. Update it. |
| Integration checks 15 to 18 and 20 skip | They need a one-time venv. See [integration/README.md](integration/README.md). |
