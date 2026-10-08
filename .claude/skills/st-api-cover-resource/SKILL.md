---
name: st-api-cover-resource
description: The full procedure for covering one Admin API 2.0 resource (tag) with examples, from the API reference to a pushed commit - read the reference, probe the lab with throwaway objects, write the bash examples and their bat twins with the bundled generators, add offline stub tests and a real-server integration check, update the docs, run the suite. Use this skill whenever someone asks to "cover", "add examples for", "do the next resource", "continue down the Admin reference", or names an Admin tag (deniedUsers, events, icapServers, ldapDomains, mailTemplates, siteTemplates, userClasses, zones, ...) to add examples for. Also use it to resume that work in a new session. Bundles tools in scripts/ for the spec, coverage, the lab, file generation and the docs.
---

# Covering an Admin API resource, end to end

This is the procedure that produced `11.Certificates`, `12.BusinessUnits`,
`13.Configurations` and `17` to `21`. Follow it in order. Each step names the
file to imitate; open that file rather than writing from memory.

Read **st-api-gotchas** before the first call, and **st-api-add-example** for
the header and naming rules. This skill is the workflow around them.

## The rule that matters most

**The reference is a claim; the lab is the truth.** Every resource so far had
something the reference gets wrong or leaves out: a required field marked
optional, a filter in milliseconds rather than seconds, a link encoded wrongly,
an answer that is a plain array, a 200 that means failure. Probe every operation
on the lab before writing the example, and write what you saw into the script's
Notes as `Confirmed directly: ...`.

## Tools (in `scripts/`, run from the repository root)

| Tool | Use |
| ---- | --- |
| `fetch_spec.sh` | Download the reference into `tests/local/admin20-spec/` (gitignored). Once per machine. |
| `endpoint.py --tags` | The tags, in the reference's order: the order we work in |
| `endpoint.py --tag NAME` | One tag's operations |
| `endpoint.py /path "/path/{id}"` | The full reference for those paths. Schemas: grep the other `.yaml` files in the spec folder for the `$ref` name |
| `coverage.py [TAG]` | Which operations no script seems to call. A heuristic: confirm by reading the folder |
| `lab.py` | `from lab import admin, show, run`: call the lab, print one line per answer, run real examples on it |
| `authoring.py` | `write_sh(...)`, then `write_bat(...)`: the house header, set up and MAIN_URL, for both twins |
| `sync_docs.py` | After adding files: recount the README table, the docs check and the pack totals. `--check` changes nothing |

`lab.py` needs `tests/local/integration.conf` (copy `tests/integration/integration.conf.example`).

**Scratch files** (the ids of throwaway lab objects, a saved password) go in the
project's own `tmp/` folder, gitignored, never in the system `/tmp`:
`from _repo import scratch_path; path = scratch_path("events_probe_ids.json")`.
Delete them when the probe is done.

## Where the work stands

Covered, in reference order: accessPolicies, accountSetup, accounts,
addressBook, administrativeRoles, administrators, applications, businessUnits,
certificates, configurations, daemons, deniedUsers, events, icapServers,
ldapDomains, loginRestrictionPolicies (the API only: see below), logs (cancel works only
for a transfer the server flags cancelable: check 48), mailTemplates, myself, routes (08 to 10 in `09.CompositeRoutes` added to the earlier create, list and delete), routeStepsMetadata (read only: one GET, `30.RouteStepsMetadata`), routeStepsCharsets (read only: one GET, `31.RouteStepsCharsets`), servers, sessions (list, read, end one session, two statistics: `32.Sessions`, check 53), sites (05 to 11 in `06.TransferSites` added to the earlier create, list and delete: HEAD, GET one, PUT, PATCH, the connection test of a saved and of a new site, the remote folder listing; check 54), statisticsSummary (read only: the usage report for a period, the users who have logged in, the platform connection test, whose success was not seen: `33.StatisticsSummary`, check 55), subscriptions (05 to 13 in `07.Subscriptions` added to the earlier create, list and delete: HEAD, GET one, PUT, PATCH, the Pull, ClearPullHistory and Purge operations, and a subscription of each of four other types with its deletion by `purge=true`; check 56), transactionManager (the status, and the stop, which was never sent to the lab and is written from the reference: `34.TransactionManager`, check 57 sends nothing but reads and refusals), transferProfiles (PeSIT only: list, create, HEAD, read, PUT, PATCH, delete, led by `advancedSettings` with the plain fields as the additional form: `35.TransferProfiles`, check 58; and what every option does to the bytes of a file, sent and stored, on 116 real pulls: check 59, with `CapturingProxy` and `pesit_wire.py`), transfers, userClasses (list, create, HEAD, read, PUT, PATCH, delete, and what a class does to the next login of an account, seen in the `userClass` of an FTP session: `36.UserClasses`, check 60; membership by an LDAP attribute was not seen), version, zones (list, create, HEAD, read, PUT, PATCH, delete, by name; what naming a zone in a business unit changes, seen over SFTP, HTTP and FTP: `37.Zones`, check 61; the effect behind a real edge was not seen).

Left out until a lab can show it: **siteTemplates** (the lab has no Connect:Direct: every create is
400 "Site template protocol cd is not valid. Connect:Direct protocol not available.", and `custom` and every
other protocol are refused too, so only list, HEAD and the unknown-id answers can be seen; see st-api-gotchas).

Left out on purpose: **clusterServices** and the cluster-only configuration
operations (the lab is standalone), the Oracle-only `database/{componentType}`,
changing the database connection, replication operations. `coverage.py`
still counts these 13 configurations operations and 2 clusterServices ones as
missing; that is expected.

**Next, in order:**
nothing: `zones`, the last tag of the reference, is done, so every tag is covered or listed above as left out. What remains: **siteTemplates**
(needs a lab with Connect:Direct), **clusterServices** and the cluster-only configuration operations (need a cluster), and the parts of
configurations left out on purpose (the Oracle-only `database/{componentType}`, changing the database connection, replication
operations). `coverage.py` with no tag lists them (plus the 13 and 2 above). Re-run `coverage.py` for the operations still missing in the
partly covered resources, and when a new release adds a tag or an operation, add it here first.

**An open question:** for loginRestrictionPolicies no behaviour test was possible. On the lab
a policy denying `*`, assigned to a business unit (and also tried with each of the two types, rules
disabled, an expression, a network, a delay of two minutes), did not stop an account of that unit
logging in over FTP (8021) or the EndUser API; SFTP login failed for other reasons. No server option
turns it on, and `isDefault` was not tried: it would apply to every account. If you learn what makes
a policy take effect (perhaps the default policy, or a restart), put it in the set up of check 46, which
already asserts the refusal and FAILS on that lab until then; check 45 covers the API and stays green.

## The procedure

### 1. Read the reference and what exists

```bash
python3 .claude/skills/st-api-cover-resource/scripts/endpoint.py --tag deniedUsers
python3 .claude/skills/st-api-cover-resource/scripts/coverage.py deniedUsers
ls "Admin/API 2.0/bash/" | grep -i denied
```

A resource with examples already gets a new script per missing operation, numbered
after the existing ones; never renumber existing files. A new resource gets the
next free folder number (look at `ls "Admin/API 2.0/bash"`; 10 is free).

### 2. Probe the lab

Some resources only show something while the server is doing something (events,
sessions, transfers in flight). Build the situation with a throwaway account,
subscription and route, and a stand-in that keeps the server waiting; see
`tests/integration/checks/42.events_scripts.py`.

Write a throwaway script in your scratchpad, never in the repository:

```python
import sys; sys.path.insert(0, ".claude/skills/st-api-cover-resource/scripts")
from lab import admin, show
show("list", admin.get("deniedUsers", params={"limit": 2}))
try:
    show("create", admin.post("deniedUsers", {"name": "example_denied"}))
    show("read",   admin.get("deniedUsers", params={"name": "example_denied"}))
finally:
    show("cleanup", admin.delete("deniedUsers/example_denied"))
```

For every operation find out: the status codes (201 with Location? 204? 200
with a body?), whether a list is `{resultSet, result}` or a plain array, which
fields are really required, what a filter accepts, what an error looks like, and
what a name with a space does. Rules:

- **Throwaway objects only**, named `example_*`, deleted in `finally`.
- **Settings:** save the value first, change, put back **exactly**, and compare
  the whole object with the saved one afterwards. If the dedicated endpoint will
  not put it back, the Server Configuration Options underneath usually can
  (see the Sentinel entry in st-api-gotchas).
- **Never** run something that changes the whole server and cannot simply be
  undone (maintenance mode, the keystore password, the database connection,
  certificates of the server itself). Write the example, test it offline, and
  say in its Notes that it was not run.
- **Outside systems** (LDAP, ICAP, SMTP, Vault, S3, Sentinel...): use or extend
  the stand-ins in `tests/integration/lib/dummy_servers.py` rather than pointing
  the lab at a real one. A new stand-in needs a test in
  `tests/checks/test_dummy_servers.py`, and must work on Linux (CI) as well as
  macOS.
- **Processes:** stop only what you started, by PID, after checking its command
  and working folder. Never `pkill -f`.

### 3. Write the bash examples

One script per operation, `NN.resource_METHOD.sh`, numbered in the reference's
order: GET list, POST, HEAD, GET one, PUT, PATCH, DELETE, then sub-resources and
operations. Write them with `authoring.write_sh`, which needs `risk=` (read, write,
config or disruptive, optionally " - why"; see st-api-add-example). Imitate:

| Shape | Look at |
| ----- | ------- |
| List with paging, a filter, one line per object | `12.BusinessUnits/02.businessUnits_GET.sh` |
| Create, print the id from Location | `11.Certificates/02.certificates_POST_generate.sh` |
| HEAD existence check | `12.BusinessUnits/03.businessUnits_name_HEAD.sh` |
| Read one, then a short summary | `13.Configurations/06.configurations_options_name_GET.sh` |
| PUT: read, edit with jq, drop metadata, send back | `12.BusinessUnits/05.businessUnits_name_PUT.sh` |
| PATCH with a JSON Patch built by jq | `13.Configurations/19.configurations_sentinel_PATCH.sh` |
| Look an object up by name when the path needs an id | `11.Certificates/04.certificates_id_HEAD.sh` |
| Multipart form (`-F`) | `13.Configurations/12.configurations_logging_name_PUT.sh` |
| A secret read from the environment | `13.Configurations/17.configurations_database_operations_POST_test.sh` |

House rules every script here follows:

- Defaults to an `example_*` object, so running it bare is harmless. A script
  that deletes or changes something real takes the name as a required argument.
- Validates its arguments and exits **2** with a usage line **before sending
  anything**; exits **1** when the server refuses; **0** on success.
- Prints `HTTP <code>` for a write, and the server's answer when it is not the
  expected code: `-w "\n%{http_code}"`, then split with `${RESPONSE##*$'\n'}`.
- Names go into a query with `-G --data-urlencode`, into a path with jq's `@uri`.
  Never follow `metadata.links` (spaces are encoded wrongly).
- JSON is built and edited with jq, never with sed or string concatenation.
- Secrets come from environment variables, never arguments.
- Notes say what the reader cannot see: what it changes, what it needs, and
  every `Confirmed directly:` finding.

### 4. Write the bat twins

`authoring.write_bat` derives the header from the bash file, so write bash
first. The body does the same thing with PowerShell in place of jq. Imitate the
twin of the bash file you imitated. Hard-won rules:

- Results of `curl` go to a temp file (`%TEMP%\x_%RANDOM%.json`), read by
  `powershell -NoProfile -Command "... Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json ..."`,
  deleted afterwards.
- Pass values to PowerShell through environment variables (`$env:NAME`), never
  by pasting them into the command: no quoting to get wrong.
- No single quotes inside a `FOR /F ('...')` command; use `$env:` there too.
- `%%{http_code}` in a bat file, never `%{http_code}` (the suite checks).
- Booleans: PowerShell prints `True`; use `([string]$x).ToLower()`.
- An arrays-of-one answer: wrap in `@(...)`.
- The bat files cannot be run here. Read each one once more against its bash
  twin before moving on: same calls, same defaults, same exit codes.

### 5. Offline tests

Add a section to `tests/checks/test_bash_admin_api.sh`, in reference order,
before the final summary. The helpers at its top: `run FOLDER/SCRIPT ARGS`
with `GET_BODY`, `SEQUENCE`, `POST_BODY`, `LOCATION`, `STATUS`, `STATUS_GET`
setting the stub's answers; `calls` (METHOD URL per line), `payload N` (the Nth
body sent), `has_header`, `body NAME JSON`, `sequence NAME JSON...`, `expect`,
`has`. The stub (`tests/lib/stub_curl`) records `-F` fields as `FORM:` lines.

Test for each script: the exact calls and URLs; the body it sends, as jq
values; what it prints from a canned answer; and that bad arguments send
nothing (`RC` 2, no calls). Reset `GET_BODY=` and friends after the section.
Fixtures are synthetic; never paste lab data into a test.

### 6. Integration check

`tests/integration/checks/NN.<resource>_scripts.py`, the next free number.
Imitate `38.business_units_scripts.py` (objects) or `40.configurations_scripts.py`
(settings, stand-ins). It runs the **real, unmodified** scripts with
`script_runner.run` inside `runner.real_credentials(...)`, checks each effect
through the API, refuses to start if an `example_*` object exists already,
cleans up in `finally`, and ends by checking nothing is left. Writes need
`--write` and `st_allow_writes`. Run it on the lab until it passes:

```bash
python3 tests/integration/checks/41.denied_users_scripts.py --write
```

Add its row to the table in `tests/integration/README.md`.

### 7. Docs and the suite

```bash
python3 .claude/skills/st-api-cover-resource/scripts/sync_docs.py 22.DeniedUsers "22. Denied Users" "\`/deniedUsers\`, ..."
./tests/run_all.sh
```

Also: a row in the task index of **st-api-orientation**; the "Next, in order"
list above; every `Confirmed directly` finding that would surprise someone
calling the API by hand goes into **st-api-gotchas**, under "The Admin API,
against its own reference".

`run_all.sh` must pass. CI runs it on **Linux**; you are probably on macOS.
Avoid `sed -i ''`, `date -j`, `stat -f`, BSD-only flags, and anything that
depends on how the OS treats sockets or threads.

### 8. Commit

Only when asked. One commit per resource or per session, staging files by
name, with nothing from `tests/local/`. No `Co-Authored-By` line. After a push,
check CI: `curl -s "https://api.github.com/repos/Axway-University-1/securetransport-rest-api-examples/actions/runs?per_page=1" | jq '.workflow_runs[0] | {head_sha, status, conclusion}'`.

## Stop and ask the user when

- the reference and the lab disagree in a way that changes what the example
  should teach (not just a status code to note);
- an operation can only be shown by changing something server-wide that you
  cannot put back exactly;
- an operation needs an outside system no stand-in covers yet, and writing one
  is more than a small HTTP or TCP fake;
- the lab is in a state that makes an operation fail for reasons unrelated to
  the example (as the login settings did).

Say what you found and what you would do; do not quietly skip the operation.
