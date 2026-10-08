# Repository improvements: what was found, what is done, what is open

Four read-only reviews of the whole repository (the example scripts, the test harness, the
documentation and skills, the python examples and the repository hygiene) found about forty
things. This is the ledger. Delete it when the open list is empty.

## Done

| Area | What | Where |
| ---- | ---- | ----- |
| Harness | Never writes over your `set_variables.local.sh` or `integration.conf`: temporary files named by `ST_ADMIN_LOCAL_VARIABLES`, `ST_ENDUSER_LOCAL_VARIABLES`, `ST_INTEGRATION_CONF`; the python config is kept on disk and restored on exit, SIGTERM, and by the next run after a SIGKILL | `tests/integration/lib/script_runner.py`, `run_integration.sh` |
| Harness | A check that asserts nothing is a skip, not a pass; output streams; timings; a name filter; number order past 99 | `run_integration.sh`, `st_client.py` |
| Harness | The mock no longer leaves its key in the temp folder, and passes check 12 and 04 | `tests/integration/mock/mock_st.py` |
| Harness | Checks that compare days wait out midnight | `st_client.avoid_midnight` |
| Secrets | Hardcoded passwords out of `stBuildFullTestAccount.py`; the credential scan covers python | `check_hygiene.sh` |
| Python | Every example: CSRF token on every write, every failure exits non-zero, every status checked, bounded waits, `daemon=` (not `serverName=`) to stop a daemon, dry run by default where it deletes, a Risk line, optional `st_verify` | `Admin/API 2.0/python`, `test_python_*.py`, `tests/lib/fake_requests` |
| Admin bash and bat | 19 scripts that changed real or server wide things when run bare, and 35 write scripts that could not fail: arguments or `example_*` defaults, `HTTP <code>`, exit 1 and 2, jq, encoded names | `test_bash_admin_api.sh`, `test_bash_admin_sweep_a.sh`, `_b.sh` |
| Admin bash | `14.ExpressionLanguage` tested and made refuse to touch what exists | `test_bash_expression_language.sh` |
| Acknowledgment | Exit codes, paging past 100 transfers, the bat twins | `90.EndToEndAcknowledgment`, `test_bash_pesit_ack.sh` |
| EndUser | Logout ended the wrong session, bash 3.2, exit 0 on failure, the tracked `test.txt`, base64 wrapping | `EndUser/API 2.0/bash`, `test_bash_enduser_api.sh` |
| Admin bash and bat | About 58 read scripts that never looked at the HTTP status (a 401 printed nothing and exited 0), the `change_me` passwords of `18.AccountSetup`, `01.myself_POST` made the login its name says | `test_bash_admin_sweep_c.sh` |
| Features | A refused call stops the run in both; the trigger feature heals a stale home folder like the billable one; clean-ups exit 1 and keep their state file; paths are encoded; shared code in `Features/lib` (`home_folder`, `admin_calls`) | `test_feature_*.sh`, `test_feature_bat_twins.py` |
| Skills | The orientation index in folder order, the covered tags as a table | `.claude/skills` |
| Repository | `.gitattributes` (CRLF for `.bat`) and the hygiene check that reads CRLF | `.gitattributes` |
| Docs | The gotchas entries later findings contradicted; an index; README, Features README, CLAUDE.md, tests README (every check named, guarded by `check_docs_match_repo.py`) | |

## Open

1. **Harness (in progress):** the copied helpers (`script()`, `wait_until`, the port lookups), the fixed sleeps in checks 43, 48
   and 56, the quiet-server assumptions of 41, 53 and 55, `mkdtemp` without cleanup, a per-check timeout, and a private output
   folder per run so that two runs do not delete each other's.
2. **Consistency:** 31 scripts need the account `john`; port 8022 is hard coded in several; some objects are not named
   `example_*` (`SSH_TEST_SERVER_*`, `RouteFrom*`, `SimpleRouteName`, `Finance`); the EndUser tree has no bat twins (decide: add
   them, or say so plainly).
3. **The bat twins have never run:** none of the bat changes could be run (no Windows here). A short run of the ones with
   PowerShell in them (`Features/lib/admin_calls.bat`, the acknowledgment scripts, `03.Connect/11`) would be worth it.
4. **Docs:** the 550 line per resource list in the gotchas is still one list; incident and history entries belong in a changelog.
5. **For the owner:** the password that was in `stBuildFullTestAccount.py` is still in git history (rotate it if it was ever
   real); `st_callback_host` in `tests/local/integration.conf` is stale, so checks 40 and 47 fail on it; the trainer kit needs
   the new arguments of the changed scripts and a new `python.tsv`; `stLinkSimpleRoute` replaces all of a route's steps with one
   `ExecuteRoute` step (data loss, or intended?).
