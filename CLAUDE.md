# Working in this repository

## Every new script and every change is covered by a test

No script or behaviour change is done until a test covers it.

- **New script**: add coverage in `tests/checks/` (offline) in the same change.
  Bash examples go through `test_bash_payloads.sh` (stub curl), python examples
  through `test_python_logic.py` (fake ST). Extend the fixtures in
  `tests/fixtures/` rather than using real data.
- **Changed script**: add or update a test that would have failed before the
  change. A bug fix starts with the test that reproduces it.
- **New endpoint behaviour the examples rely on**: add an integration check in
  `tests/integration/checks/`, runnable with `--mock`.
- Run `./tests/run_all.sh` and confirm it passes before calling the work done.
  It must stay offline: no server, no credentials, no network.
- Test data is synthetic. Nothing from a real server goes into `tests/fixtures/`;
  captured data belongs in `tests/local/`, which git ignores.

CI (`.github/workflows/tests.yml`) runs `tests/run_all.sh` on **Linux** on every
push and pull request; check it after a push. Also follow
`.claude/skills/st-api-add-example` for house style.

## Admin API coverage

Examples are being added one Admin API resource at a time, in the order of the
API reference. `.claude/skills/st-api-cover-resource` is the procedure, the
list of what is done and what is next, and the tools (spec, coverage, lab,
generators, docs sync). Follow it step by step; update its list when a
resource is done.

## Which model

- **Sonnet** for covering the next resource by that procedure: reading the
  reference, probing the lab, writing the scripts, bat twins, tests and docs.
  `.claude/agents/st-api-resource-author.md` runs it as a subagent.
- **Opus** for what the procedure does not cover: a new kind of stand-in
  server, a change to the test harness or the tools, a lab finding that
  changes what an example should teach, a CI failure that does not reproduce
  on macOS, and reviewing a finished resource before it is committed.

## Safety on the lab

- Probe with throwaway `example_*` objects; put any changed setting back
  exactly and compare it with the saved copy.
- Never run what changes the whole server and cannot be undone (maintenance
  mode, the keystore password, the database connection).
- Stop only processes you started, by PID, after checking their command and
  working folder.

## Feature examples

New product-release features go in `Features/<feature-name>/` (by feature, not by
release). Each script starts with the version check from `Features/lib/`, using
the release that introduced the feature, and the feature is added to
`Features/README.md` and the main README under that release. The whole procedure
is in `Features/README.md` under "Adding a feature".
