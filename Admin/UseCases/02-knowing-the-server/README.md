# 02 Knowing the server

**Use case:** find out what you are talking to and how it is set up, without changing anything: the release, the listeners, the servers, who has logged in, a setting among a thousand, how logins are configured, and who is connected now.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`Admin/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

Everything here is a read. The answers are JSON and mostly bigger than a script needs, so each one is narrowed with `jq`, and the long
ones are read in pages (`limit` and `offset`, with `resultSet.totalCount` saying how many there are in all).

## The examples

Run them in order: each one builds on the one before it (`00.run_all.sh` runs
them all, and ends with `99.cleanup_DELETE.sh`). The scripts of `02` check for an active session
first and log in when there is none, so each can also be run on its own.

| Script | What it does | Copied from (`Admin/API 2.0/bash`) |
| ------ | ------------ | ---------------------------------- |
| `01.version_GET` | The release, build, system and plugins, narrowed. | `02.Introduction/01.version_GET.sh` |
| `02.daemons_GET` | Which protocol daemons are running. | `03.Connect/01.daemons_GET.sh` |
| `03.servers_GET` | The servers, one line each, counted by protocol. | `03.Connect/06.servers_GET.sh` |
| `04.statisticsSummary_activeUsers_GET` | A long list read in pages of 5. | `33.StatisticsSummary/02.statisticsSummary_activeUsers_GET.sh` |
| `05.configurations_options_GET` | One setting among a thousand: counts, the modified ones, a name pattern with `*`. | `13.Configurations/03.configurations_options_GET.sh` |
| `06.configurations_settings_GET` | How logins are configured and whether maintenance mode is on. | `13.Configurations/21.configurations_loginSettings_GET.sh and 24.configurations_maintenance_GET.sh` |
| `07.sessions_GET` | Who is connected now, counted by protocol. | `32.Sessions/01.sessions_GET.sh` |
| `99.cleanup_DELETE` | Ends the session. Nothing was created. |  |

`lib.sh` is the one small file they share: it loads `../session.sh` (the settings, `ST_URL`, the cookie
jar of this use case, `session.cookie.jar`, which git ignores, and the session helper `st_session`).

## What to take from it

- Most answers are `{resultSet, result}`: `returnCount` is what came back, `totalCount` how many there are. Ask for `limit=1` to count cheaply.
- A list with no `limit` is cut at 100: read everything by adding the page size to the offset until it passes `totalCount`.
- `GET /configurations/options` takes `name=` with `*` as a wildcard and `isModified=true` for what differs from the default.
- A running daemon does not mean a server is listening: a server is a separate object.
- Starting and stopping daemons and servers, and maintenance mode, are not here on purpose: they change the whole server.

## Tests

`tests/checks/test_bash_admin_usecases.sh` runs every script against a stub `curl`.
`tests/integration/checks/64.admin_usecases_scripts.py` runs them on a real server and compares the release and the number of
servers they print with what it reads itself.
