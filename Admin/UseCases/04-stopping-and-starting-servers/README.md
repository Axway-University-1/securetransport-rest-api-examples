# 04 Stopping and starting servers

**Use case:** an administrator stops one protocol daemon for maintenance, waits until it is really down, starts it again, waits until it and its servers are really up, and proves that everything is as it was before.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`Admin/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).
>
> **This stops a daemon of the whole server.** Every client of that protocol is refused until it is started again. Run it on a server that is yours, on a daemon nobody is using. The scripts take the daemon as a parameter, `ftp`
> when it is left out of `00.run_all.sh` and `99.cleanup_DELETE.sh`. They never stop or start the AS2 daemon (see "What to watch").

## The story

You have to restart the FTP service: a certificate was changed, or a port, or a patch needs the listener down. Before you touch anything you write down what is running. Then you stop the daemon, and you do **not** go on when the server says "OK":
the answer to a stop or a start comes first, and the daemon follows seconds later. So you wait, with a limit, for the status you expect. Then you do the same for the servers of the protocol, which come up on their own after the daemon.
At the end you compare with what you wrote down. If anything is not as it was, you put it back.

## The examples

Run them in order. `00.run_all.sh [DAEMON]` runs 01 to 06 (03 twice) and ends with `99.cleanup_DELETE.sh`, which puts back whatever a failed step left stopped.

| Script | What it does | Copied from |
| ------ | ------------ | ----------- |
| `01.daemons_GET` | The status of every daemon and which servers are active. **Saves them** in `state.local.daemons.json` and `state.local.servers.json`. | `Admin/API 2.0/bash/03.Connect/01.daemons_GET.sh` and `06.servers_GET.sh` |
| `02.daemon_stop DAEMON stop-the-DAEMON-daemon [GRACEFUL] [TIMEOUT]` | `POST /daemons/operations?operation=stop`. Needs the confirmation word. `GRACEFUL` is `true` unless you say `false`, written out in the call. Reads `isSuccessful` and says what each answer means. | `03.Connect/05.daemons_operations_POST.sh` |
| `03.daemon_wait DAEMON STATE [SECONDS]` | Polls `GET /daemons` every 3 seconds until the daemon says `Running` or `Not running` (quote it), and says how long it took. Exit 1 when it does not in time (60 seconds unless you say). | written for this use case |
| `04.daemon_start DAEMON` | `POST /daemons/operations?operation=start`. Reads `isSuccessful`. The answer comes before the daemon is up. | `03.Connect/05.daemons_operations_POST.sh` |
| `05.servers_wait DAEMON [SECONDS]` | Waits until the servers of that protocol that were active at the start are active again. A server still down when the time is up is started with `POST /servers/operations` (its answer read for `isSuccessful`), and the wait runs once more. | `03.Connect/06.servers_GET.sh` and `13.servers_operations_POST.sh` |
| `06.compare_with_start` | Reads everything again and compares it with the copy 01 saved: each difference printed, exit 1 when there is one. "Nothing is different" is the proof. | written for this use case |
| `99.cleanup_DELETE [DAEMON]` | If the daemon was Running at the start and is not now, starts it and waits; if a server of it was active and is not, starts it and waits. Then removes the copy and the session. Can be run twice. | written for this use case |

`lib.sh` is the shared file: the settings and the session (`../session.sh`), and the helpers that read a status, wait, and read the answer of an operation.

## What each step shows

1. **Write down the state first (01).** The daemons answer is one object with a key for each daemon (`ftpStatus`, `httpStatus`, ...). The servers answer is a list, and each server has the `protocol` of its daemon: that is how a daemon is tied to its servers.
2. **A stop needs a word (02).** Like `05.daemons_operations_POST.sh`, the script sends nothing unless you give `stop-the-ftp-daemon`. A script that stops a service for everyone should not do it by accident.
3. **Write `graceful` in full (02).** The server does not check it: `graceful=yes`, `graceful=maybe` and no `graceful` at all **stop the daemon at once** (tried: `graceful=yes` answered "Daemon FTP is stopped."). So this script refuses anything but `true` or `false`,
   before a call, with exit 2. A graceful stop answers at once ("Submitted graceful shutdown for daemon FTP.") and finishes in the server, in its own time; a `timeout` is how long it gives the connections in progress, and it goes only with `graceful=true`.
4. **A 200 can say no (02, 04, 05).** The operations answer 200 when they did not work: read `isSuccessful`. A start of a running daemon is 200 with `isSuccessful` false and "Daemon FTP is already started."; a server that does not exist, 200, false,
   "Server with name ... does not exist."; the AS2 daemon with its listener off, 200, false, "Can not start AS2 daemon - the default server As2 Default is not enabled.". The scripts print the message and exit 1.
5. **Wait for the state, not for the answer (03).** A stop is accepted, and the daemon stays `Running` for a while, shows `Graceful shutdown in progress.`, and then `Not running`. A start is accepted, and the daemon is `Not running` for about 10 more seconds. So poll, with a limit.
6. **The servers follow the daemon (05).** Start a daemon and its servers come back by themselves a few seconds after it says `Running`; stop it and they go down with it. You do not stop or start them one by one. A server start sent too early is refused
   ("... The FTP daemon is not started. Start the daemon and try again."), so 05 waits first, and starts a server only when it is still down after the wait.
7. **Prove it (06).** Everything that was running is running, every server that was active is active. Without this, "it worked" is a guess.
8. **Put back what is not as it was (99).** Run it after a failure: it finds the daemon stopped, starts it, waits, and does the same for the servers.

## What to watch

### One answer, two shapes

| Operation | The answer |
| --------- | ---------- |
| `POST /daemons/operations` | a **list**: `[{daemon, message, isSuccessful}]` (the reference describes an object with `daemonOperationResults`: the scripts read both) |
| `POST /servers/operations` | an **object**: `{serverStatuses: [{serverName, message, isSuccessful}]}` |

```bash
# every result that did not work, from either shape
jq -r '(if type == "array" then . else (.serverStatuses // .daemonOperationResults // []) end)[] | select(.isSuccessful != true) | "\(.serverName // .daemon): \(.message)"'
```

An answer with no result is not a success. A wrong request is a different thing: an unknown daemon is **400** "Not correct daemon type: nope. Possible values are: ftp, http, ssh, pesit or as2.".

### Times on the lab (the FTP daemon, 5.5-20260924)

| What | Seen |
| ---- | ---- |
| The answer to a **graceful stop** | at once; the daemon says `Running` for about 8 to 20 seconds more, then `Graceful shutdown in progress.`, then `Not running` (10 to 22 seconds after the answer with no connection open; a longer wait with connections, up to the `timeout`) |
| The answer to a **stop that is not graceful** | after the daemon is stopped, 9 to 15 seconds |
| The answer to a **start** | at once |
| The daemon says `Running` | 11 to 15 seconds after the answer to the start |
| The servers of the daemon are active | 1 to 4 seconds after that (15 to 19 seconds after the answer in all) |

- **The Admin API answers slowly while a daemon changes state.** A `GET /daemons` that is sent then can take 8 to 10 seconds to answer. Each poll can be that long, so the time 03 reports is the clock, and not 3 seconds for each try.
- **Two sessions can disagree for a few seconds.** Right after one session read `Running`, another read `Not running` for about 4 seconds more. Do not take one read as the end of the matter: wait for the servers as well.
- A status is one of `Running`, `Not running`, `Graceful shutdown in progress.` (with its full stop). The reference lists `Shutdown` and `Pending shutdown` too, which the lab did not show. 03 waits for the exact text it is given and says the last one it saw when it gives up.

### Things that are the same for a person and a script

- **A stop of a daemon that is already stopped** is answered 200, "Submitted graceful shutdown for daemon FTP.", `isSuccessful` true, and changes nothing (the daemon was still `Not running` 20 seconds later). A start of one that is running says
  "already started" and false. The scripts read the status first and send neither.
- **Never kill a script that sent a graceful stop and then start the daemon.** A stop that was submitted can still arrive later and undo the start. 03 first, then 04.
- **The AS2 daemon is not stopped or started here.** On a server whose AS2 listener is switched off it cannot be started again (200, `isSuccessful` false). `00.run_all.sh` and `99.cleanup_DELETE.sh` refuse `as2` with exit 2.
- **Do not stop what your session runs on.** The End User API of this lab is on the http daemon: the scripts ask for the daemon by name, and a person must not give `http` while that matters.
- **`GET /daemons/{name}` takes only `ssh`** (400 "Invalid value for parameter name, expected (ssh)" for the others). Read all daemons with `GET /daemons`, as 01 does.
- **The Transaction Manager can be stopped through the API and cannot be started** (`POST /transactionManager/operations?operation=start` is 400). Do not stop it from a script.
- A server's name has a space: let curl encode it (`--data-urlencode "serverName=Ftp Default"`).

## Tests

`tests/offline/checks/test_bash_admin_usecase_04.sh` runs every script against a stub `curl` and checks each call, each exit code and each message: a stop with no word, with a `graceful` that is not true or false, with an answer that says no or is refused, the wait
loop against a sequence of statuses (and its timeout), a difference found by 06, `00.run_all.sh` stopping at a failing step and still cleaning up, and the cleanup run twice.
`tests/online/checks/71.admin_usecase_stopping_and_starting.py` runs the use case for real on the FTP daemon: it proves through its own session that the daemon is `Not running` after 02 and 03 and `Running` after 04, that its servers are active after 05,
that 99 puts back a daemon a run left stopped, and that every daemon and server is as it was at the start. It stops only the FTP daemon, takes about 3 minutes, and starts the daemon again whatever happens.
