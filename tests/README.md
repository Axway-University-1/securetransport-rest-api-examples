# Tests

Checks for the examples in this repository. **Everything here runs offline** —
no SecureTransport server, no credentials, no network. That is deliberate: these
checks should run on any clone, on any machine, before you have configured
anything.

```
./tests/run_all.sh
```

## What is checked

| Check | What it catches |
| ----- | --------------- |
| `checks/check_hygiene.sh` | A credential, hostname, IP or customer name committed by accident. Naming that drifts from the convention. A shell file that does not parse. A bash example with no bat twin. |
| `checks/check_readme_counts.py` | The README coverage tables claiming a count that no longer matches the directories. |
| `checks/check_knowledge_pack.py` | The `.claude` skills describing a layout, file or variable that no longer exists. |
| `checks/test_bash_payloads.sh` | A curl example emitting malformed JSON, or an unexpanded `${VARIABLE}`, by running it against a stub `curl` that prints the payload instead of sending it. |
| `checks/test_python_logic.py` | The python examples doing the wrong thing, by running them against a fake ST that serves paged collections and records what they would write. |

The last two are the interesting ones. They exercise the real scripts without a
server, which is how the silent JSON corruption described in
`.claude/skills/st-api-gotchas/SKILL.md` was found.

## Against a real server

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
[integration/README.md](integration/README.md).

## Layout

```
tests/
    run_all.sh          runs everything
    lib/                the stubs: a fake curl, a fake ST API
    fixtures/           small synthetic inputs. No real data, ever.
    checks/             the checks themselves
    integration/        opt-in checks against a real server. See its README.
    local/              YOUR data. Git ignores this. See below.
    output/             run artifacts. Git ignores this.
```

## tests/local — the part git ignores

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

## Adding a check

Drop an executable script into `checks/`. `run_all.sh` discovers anything named
`check_*` or `test_*` and expects exit code 0 for pass. Keep it offline, and keep
it fast — the point is that people actually run it.
