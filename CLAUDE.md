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

CI (`.github/workflows/tests.yml`) runs `tests/run_all.sh` on every push and pull
request. Also follow `.claude/skills/st-api-add-example` for house style.
