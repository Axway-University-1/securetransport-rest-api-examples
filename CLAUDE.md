# Working in this repository

## Every new script and every change is covered by a test

No script or behaviour change is done until a test covers it.

- **New script**: add coverage in `tests/checks/` (offline) in the same change,
  in the file for its tree: Admin bash examples in `test_bash_admin_api.sh`,
  EndUser in `test_bash_enduser_api.sh`, Features in `test_feature_*.sh`, the
  acknowledgment loop in `test_bash_pesit_ack.sh`, Expression Language in
  `test_bash_expression_language.sh` (all with the stub curl), python examples in
  `test_python_*.py` (whole scripts run against `tests/lib/fake_requests`, a stand-in
  server that refuses a write without a csrfToken). `test_bash_payloads.sh` runs
  every Admin example generically: give it the arguments a new one needs. Extend
  the fixtures in `tests/fixtures/` rather than using real data.
- **Changed script**: add or update a test that would have failed before the
  change. A bug fix starts with the test that reproduces it.
- **New endpoint behaviour the examples rely on**: add an integration check in
  `tests/integration/checks/`, runnable with `--mock`.
- Run `./tests/run_all.sh` and confirm it passes before calling the work done.
  It must stay offline: no server, no credentials, no network.
- Test data is synthetic. Nothing from a real server goes into `tests/fixtures/`;
  captured data belongs in `tests/local/`, which git ignores.

CI (`.github/workflows/tests.yml`) runs `tests/run_all.sh` on **Linux** on every
push and pull request; check it after a push. `.gitattributes` gives `.bat` files
CRLF on a checkout, which a macOS working tree does not show: before a push, run
the suite in a fresh `git clone` of the commit. Parallel runs share `tests/output`,
so a full run next to another one can fail oddly: use a clone for it. Also follow
`.claude/skills/st-api-add-example` for house style.

## Admin API coverage

Every resource of the Admin API reference has examples, except by design
`siteTemplates` (the lab has no Connect:Direct), `clusterServices` and the
cluster-only configuration operations (the lab is standalone), and the
database, replication and Oracle-only configuration operations.
`.claude/skills/st-api-cover-resource` is the procedure for a resource a new
release adds, with the list of what is covered and the tools (spec, coverage,
lab, generators, docs sync). Update its list when a resource is added.

## Which model

- **Sonnet** for covering a new resource by that procedure: reading the
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
