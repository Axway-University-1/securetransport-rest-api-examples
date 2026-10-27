# Starting and stopping protocol servers and daemons through the REST API

**For:** operators and administrators who stop and start the protocol daemons and servers of SecureTransport with scripts, for maintenance, tests or recovery.
**Checked on:** SecureTransport 5.5-20260924, on a lab with one FTP, one SSH, one PeSIT, one AS2 and two HTTP servers. Where the text says "tried", it was run on this
lab, and every daemon and server was put back and checked. The times are what that lab showed: yours will differ, but the pattern is the same. A statement marked
"not tried" comes from the API reference or from the notes of this repository. In this guide, "the lab" is the test server that it was checked on.

## Summary

- A **daemon** runs one protocol (FTP, HTTP, SSH, PeSIT, AS2). A **server** is a listener of that protocol, with its own port. Stop a daemon, and its servers stop.
  Start a daemon, and its servers come back **by themselves, about 3 to 8 seconds after the daemon says `Running`**.
- Both operations answer **200 even when the operation fails** (a request that is wrong, such as an unknown daemon name, is a 400). Read `isSuccessful` in the answer, and the `message`.
- The answer to a daemon **start** comes in half a second. The daemon is `Running` **about 11 seconds later**, and its servers are active 15 to 19 seconds after the answer.
  Do not start a server in that time: it is refused. Start the daemons first, wait until each says `Running`, then look at the servers.
- A **graceful** stop answers at once, and the stopping goes on in the server. A stop that is **not graceful** answers after the daemon has stopped, 9 to 15 seconds later.
- A mistake in the `graceful` parameter is not an error: `graceful=maybe` stopped the daemon at once.
- Whatever your script stops, it must put back, and check that it did.

## Daemons and servers

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons" -H "accept: application/json" -H "Referer: x"
```

```text
{ "ftpStatus" : "Running", "httpStatus" : "Running", "pesitStatus" : "Running", "sshStatus" : "Running", "as2Status" : "Not running" }
```

A status is one of these (tried: the first, the second, and the third during a graceful stop):

| Status | Meaning |
| ------ | ------- |
| `Running` | The daemon is up |
| `Not running` | It is stopped |
| `Graceful shutdown in progress.` | A graceful stop is going on. This text, with its full stop, is what the lab showed. |
| `Shutdown`, `Pending shutdown` | Listed in the reference (not tried: the lab did not show them) |

The servers are listed at `GET /servers`. Each has a `serverName`, a `protocol` and `isActive`. On the lab:

| Daemon | Servers on it |
| ------ | ------------- |
| ftp | `Ftp Default` |
| http | `Http Default`, `S3 Only` |
| ssh | `Ssh Default` |
| pesit | `Pesit Default` |
| as2 | `As2 Default` |

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers" \
  --data-urlencode "fields=serverName,isActive" --data-urlencode "limit=200" -H "accept: application/json" -H "Referer: x"
```

The answer always carries `serverName` and `protocol`, even when you do not ask for them, so you can tell the servers apart.

## Operations on a daemon

`POST /daemons/operations`, with the parameters in the query:

| Parameter | Values | Notes |
| --------- | ------ | ----- |
| `operation` | `start`, `stop` | Required |
| `daemon` | `ftp`, `http`, `ssh`, `pesit`, `as2` | An unknown name is **400** "Not correct daemon type: nosuch. Possible values are: ftp, http, ssh, pesit or as2." The reference says that for a start, leaving it out starts all daemons (not tried: give the name every time). |
| `graceful` | `true`, `false` | Only for `stop`. See below. |
| `timeout` | seconds | For a graceful stop: how long to wait for the connections in progress |

The answer is a **list**, one entry for each daemon (the reference documents an object that holds the list; the lab answers the list itself):

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/operations?operation=start&daemon=ftp" \
  -H "accept: application/json" -H "Referer: x"
```

```text
[ { "daemon" : "FTP", "message" : "Daemon FTP is started.", "isSuccessful" : true } ]
```

The messages that were seen:

| Request | `isSuccessful` | `message` |
| ------- | -------------- | --------- |
| Start a daemon that is stopped | true | `Daemon FTP is started.` |
| Start a daemon that is running | **false** | `Daemon FTP is already started.` |
| Stop, not graceful | true | `Daemon FTP is stopped.` (after 9 to 15 seconds) |
| Stop, graceful | true | `Submitted graceful shutdown for daemon FTP.` (at once) |

The answer code is 200 in all four. A `false` with a 200 is not an error of the request: it says what happened.

### The `graceful` parameter

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/operations?operation=stop&daemon=ftp&graceful=true&timeout=40" \
  -H "accept: application/json" -H "Referer: x"
```

| What was sent | What the server did |
| ------------- | ------------------- |
| `graceful=true&timeout=40` | Answered at once. The daemon went on running, then showed `Graceful shutdown in progress.`, then `Not running`. |
| `graceful=false` | Stopped the daemon, and answered when it was done. |
| `graceful=false&timeout=10` | The same. The timeout was ignored, and no error was given. |
| no `graceful` at all | **Stopped the daemon at once.** |
| `graceful=maybe` | **Stopped the daemon at once.** A value that is not `true` or `false` is not refused. |

So write `graceful=true` in full, and never leave it out when you want the connections to finish. A typo does not stop the request, it makes it harder.

## Operations on a server

`POST /servers/operations`, with `serverName` and `operation` (`start` or `stop`) in the query. The answer is an **object** with a list, `serverStatuses`:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/operations" \
  --data-urlencode "serverName=Ftp Default" --data-urlencode "operation=start" -H "accept: application/json" -H "Referer: x"
```

```text
{ "serverStatuses" : [ { "serverName" : "Ftp Default", "message" : "The port 8021 is in use.", "isSuccessful" : false } ] }
```

The server name has a space: let curl encode it (`--data-urlencode`). The answers that were seen, always with the code 200:

| Request | `isSuccessful` | `message` |
| ------- | -------------- | --------- |
| Start a server whose daemon is stopped | false | `Can not start server Ftp Default. The FTP daemon is not started. Start the daemon and try again.` |
| Start a server that is already active | false | `The port 8021 is in use.` (there is no message that says "already active": the port is used by the server itself) |
| A server that does not exist | false | `Server with name No Such does not exist.` |

Two points. A server start can **take a long time to answer**: one that was sent while the daemon was not running was refused after 10 seconds. The message "the port is in use"
for a server that is active is not a problem. Look at `isActive` before you start a server, and do not start one that is active.

## How long it takes

Measured on the lab, from the moment the call was sent. Each line is one stop and one start. The stop was not graceful, and the server is the one of that daemon.

| Daemon | Stop answered after | Start answered after | Daemon `Running` after the start | Server active after the start |
| ------ | ------------------- | -------------------- | -------------------------------- | ----------------------------- |
| FTP, round 1 | 9.7 s | 0.5 s | 12.3 s | 15.8 s |
| FTP, round 2 | 12.7 s | 0.4 s | 12.0 s | 15.3 s |
| FTP, round 3 | 12.7 s | 0.4 s | 11.0 s | 15.2 s |
| HTTP, one round | 8.8 s | 0.5 s | 11.0 s | 19.4 s (`Http Default`) |

What this means for a script:

- **The answer to a start is not the end of the start.** The daemon needs about 11 to 12 seconds more, and the server 3 to 8 seconds after that.
- A **stop** answers when the daemon is `Not running`, so after it you can go on at once.
- A server start sent half a second after the daemon start waited 10.5 seconds and was refused with "The FTP daemon is not started". Then the daemon and the server
  came up by themselves, 5 seconds later. The refused call did no harm, and was not needed.

## The order, and waiting

1. Start the **daemons**, one by one. Check `isSuccessful` in each answer.
2. Wait until each daemon you started says `Running`, with a limit (below).
3. Wait a few more seconds: the servers of the daemon come up by themselves.
4. Read the servers. Start only those that are not active. Look again before you call one a failure.

To stop, you stop only the daemon: its servers stop with it, and you do not stop them one by one.

### A loop that waits for `Running`

```bash
# wait_daemon DAEMON [SECONDS]: waits until GET /daemons says Running for the daemon; gives up after SECONDS (default 60)
wait_daemon() {
  local daemon="$1" limit="${2:-60}" waited=0 status
  while [ "${waited}" -lt "${limit}" ]; do
    status=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons" \
      -H "accept: application/json" -H "Referer: x" | jq -r --arg key "${daemon}Status" '.[$key]')
    [ "${status}" = "Running" ] && return 0
    sleep 3
    waited=$((waited + 3))
  done
  echo "the ${daemon} daemon is not Running after ${limit} seconds (last status: ${status})" >&2
  return 1
}
```

Use it like this:

```bash
# start the daemon, check the answer, wait for Running, then give its servers a few seconds
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/operations?operation=start&daemon=ftp" \
  -H "accept: application/json" -H "Referer: x" | jq -e '.[0].isSuccessful' > /dev/null || echo "the start was refused"
wait_daemon ftp 60 && sleep 5          # then its servers are up, or nearly
```

A limit of 45 to 60 seconds is enough on the lab for one daemon. Do not wait for ever: a daemon that cannot start (see AS2, below) never says `Running`.

## A graceful stop goes on without you

A graceful stop gives the connections in progress time to finish, up to `timeout` seconds. It answers at once with "Submitted graceful shutdown", and the work is done
by the server, in its own time. Tried on the FTP daemon, with an FTP session open: the client that sent the stop had left after a tenth of a second. The daemon
showed `Running` for 11 seconds, then `Graceful shutdown in progress.`, and was `Not running` 23 seconds after the call.

What follows from it:

- **The answer is not the stop.** Poll `GET /daemons` until it says `Not running`.
- **Never kill the script that sent a graceful stop and then start the daemon again.** A stop that was already submitted can still arrive later and undo the start.
  This was the cause of a real outage during the development of the examples in this repository (from its notes, not tried again here).
- **Put back every server too.** A stopped daemon makes its servers inactive: save the `isActive` of every server before you stop anything, and compare after.
- **Check twice**, with a wait in between as long as the `timeout` you gave. This catches a stop that was still pending at the first look.

## What does not work

| What | What the server says |
| ---- | -------------------- |
| `GET /daemons/ftp`, or any name but `ssh` (also `PUT` and `PATCH`) | **400** "Invalid value for parameter name, expected (ssh)". Only `ssh` is accepted there (`GET /daemons/ssh` is 200). |
| `POST /transactionManager/operations?operation=start` | **400** `stopGracefully.arg1 must match "(?i)(stop)"`. The Transaction Manager can be stopped through the API, and there is no way to start it again. |
| Starting the AS2 daemon when the AS2 listener is switched off | **200**, with `isSuccessful` false and "Can not start AS2 daemon - the default server As2 Default is not enabled." (from the notes of this repository: not tried here, AS2 was left alone) |

Never stop the Transaction Manager from a script that has to start it again. For AS2, switching the listener off is a different setting from stopping the daemon. If the AS2 daemon
does not come up, your call may not have failed: the listener may be switched off. Read the message.

## The confirmation words of the examples

The example scripts in `Admin/API 2.0/bash/03.Connect` stop nothing unless you give a word that says so. This is on purpose:

| Script | To stop, give | To start everything that is stopped |
| ------ | ------------- | ----------------------------------- |
| `05.daemons_operations_POST.sh` | `stop-the-ftp-daemon` (the daemon's name in it) | |
| `13.servers_operations_POST.sh` | `stop-the-Ssh Default-server` (the server's name in it) | `--all-stopped start-all-stopped-servers` |

`13.servers_operations_POST.sh --all-stopped` follows the order of this guide. It starts the daemons that are stopped and waits for them to say `Running`. Then it
starts the servers that are not active, and looks again before it calls one a failure.

## Checklist

- [ ] The state of every daemon and every server was saved before anything was stopped.
- [ ] `graceful` is written in full: `true` for a graceful stop, `false` for an immediate one. Never left out, never misspelt.
- [ ] `isSuccessful` is read in every answer, whatever the code.
- [ ] After a start, the script waits for `Running` with a limit, and a few seconds more, before it looks at the servers.
- [ ] A server that is active is not started again.
- [ ] After a graceful stop, the script polls until `Not running`, and does not start the daemon again before.
- [ ] At the end, every daemon and server is compared with the saved state.
