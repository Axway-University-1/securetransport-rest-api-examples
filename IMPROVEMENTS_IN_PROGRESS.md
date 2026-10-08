# Repository Improvements - Completion Status

This document tracks the systematic improvements to the examples repository identified in the full repo scan (October 2025).

## Completed (5 commits)

### Priority 0: Safety ✅
1. **Config file protection** - Script harness now writes backups to disk and restores on SIGTERM, preventing loss of developer config when process is killed
2. **Password literals** - Replaced 4 hardcoded passwords in stBuildFullTestAccount.py with "change_me" placeholder
3. **Hygiene check extended** - Credential scan now covers Python files, rejecting any password line unless explicitly "change_me"

### Priority 1a: Python script errors ✅
- Fixed undefined names in 7 python scripts (et→e in exception handlers, urlrl→stUrl, writelog→writeLog, stURL→stUrl)
- Result: error paths no longer crash with NameError/TypeError

### Priority 1b: Line endings ✅
- Added `.gitattributes` forcing CRLF for `.bat` files to prevent cmd.exe label resolution bugs in files >512 bytes

### Priority 3a/3b: README documentation ✅
- Added 14.ExpressionLanguage to Admin table
- Fixed parity claim (bash/bat match except EL)
- Updated intro and glossary
- Fixed stale "not covered" list

---

## Remaining Work (Organized by Priority)

### Priority 1c: Dangerous script defaults (HIGH RISK - 5 scripts)
These scripts change the server when run with default arguments:

| Script | Issue | Fix |
|--------|-------|-----|
| `02.myself_PATCH.sh` | Changes admin password to placeholder | Require `$1` (new password) or exit 2 |
| `03.daemons_name_PUT.sh` | Modifies real daemon settings | Require daemon name + values as args |
| `04.daemons_name_PATCH.sh` | Patches daemon | Require daemon + values as args |
| `05.daemons_operations_POST.sh` | Stops SSH daemon forever | Require daemon + operation + confirmation word |
| `13.configurations_PATCH.sh` | Writes placeholder client secrets | Require env vars for all 10 settings |

**Testing:** Verify each rejects with exit 2 when args missing.

### Priority 1d: Exit codes (88 bash + 79 bat scripts)
Most scripts ignore HTTP errors and always exit 0. Fix pattern:

```bash
# Check status and exit on error
HTTP_CODE=$(curl ... -w "\n%{http_code}" ... | tail -1)
[ "$HTTP_CODE" = "204" ] || exit 1
```

**Affects:** All 02/03 folders plus any PUT/PATCH/DELETE.
**Testing:** Verify script exits 1 when server returns 400 or 500.

### Priority 1e: Broken bat files (4 files)
| File | Issue | Fix |
|------|-------|-----|
| `03.Connect/11.servers_name_PATCH.bat` | PATCH sends object, not array | Use `ConvertTo-Json -InputObject @(...)` |
| `04.Applications/02.applications_POST.bat` | PowerShell null bug (IF "%NAME%"=="null") | Use `if ($null -eq $var)` |
| `90.Acknowledgment.bat` | Unquoted URL has &, Get-Date broken | Quote safely, fix format string |
| `90.IteratePesitInbounds.bat` | Double CALL expansion corrupts URL | Use `%~2` not `%2` |

### Priority 1f: EndUser bash scripts (7 scripts)
| Issue | Scripts | Fix |
|-------|---------|-----|
| Bare exit after error | 01/01, 01/02, 02/03, 02/05, 02/06 (×2), 02/07 | Replace `exit` with `exit 1` |
| bash 3.2 substring error | `01.Authenticate/01.myself_POST.sh` | Use `printf` instead of `${...:-3}` |
| Overwrites cookie jar | `02.myself_DELETE.sh` | Use `-b` (read jar) not `--cookie-jar` |
| Appends to tracked file | `02.Files/04.files_filepath_POST.sh` | Use temp file, not tracked `test.txt` |
| base64 line wrapping | `set_variables.sh` | Pipe through `tr -d '\n'` on Linux |

### Priority 2: Test harness (61 integration checks)
Major gaps (estimated 2-3 days of work):

- **Missing offline tests:** folders 01-05 (200+ scripts), 14.ExpressionLanguage (8 scripts), 10 python programs
- **Flaky checks:** 56, 43, 48, 55, 30 use sleep-based assertions or absolute dates
- **Duplicated helpers:** `script()` (34 copies), `wait_until` (9), port lookups (19) - move to `tests/integration/lib`
- **Temp file leaks:** 89 leftover `mock_st_*` directories; mock_st.py never removes them
- **Mock failures:** 
  - Check 12: version/myself endpoints lack fields
  - ~29 checks report "PASS 0 assertions" instead of SKIP

**Fix sequence:** helpers first, then flakiness, then missing tests.

### Priority 3: Documentation restructure (20+ hrs)

- **Gotchas skill:** 1500 lines, 10 contradictions, no index. Needs: index, one section per resource, cross-cutting tables.
- **Test READMEs:** stale counts, wrong mock failure reason
- **Orientation skill:** out-of-order task index, stale descriptions
- **CLAUDE.md:** obsolete "add next resource" instructions

---

## How to Continue

**Start with Priority 1c** (5 scripts) → **Priority 1d** (pattern fix for 167 scripts) → **Priority 1e/1f** → **Priority 2** → **Priority 3**.

Each priority is independent. Can parallelize 1c and 1d, or do them serially then test batch.

Every change should be tested with:
```bash
./tests/run_all.sh                           # offline
python3 tests/integration/checks/NN.*.py     # on lab
```

Then committed as a batch: `Priority 1c: <concise summary>`, etc.

---

## Notes for Next Session

- All 5 completed batches pass `./tests/run_all.sh` offline (17 checks).
- No integration lab tests were run for the fixes yet.
- `.gitattributes` is in place but files haven't been re-normalized yet (optional; happens on next clone if users run `git reset --hard`).
- The harness backup mechanism uses `tests/.harness_backups/` on disk to survive SIGTERM; can be cleaned up if runs complete normally.
