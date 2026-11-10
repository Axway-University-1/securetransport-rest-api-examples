# 10 QLT events generation

**Use case:** SecureTransport reports what happens to every transfer as **events**, over the QLT protocol, to Axway Sentinel, Workbench or Event Router. An administrator wants to
see those events, to know what a product that receives them will get, without having any of those products. This use case does it with none of them: it tells the server to report
to an address that nothing answers, so that the server keeps the events in a **file** (the overflow file), runs a flow, and reads the events of the flow out of the file. It does that
for **two scenarios**, each recorded in a file of its own, so that the events of one scenario are never mixed with the other's.

> **For test environments only, and this one changes the whole server.** Read the [Disclaimer](../../../README.md#disclaimer) and the next section before running anything. The connection
> settings are the ones of [`Admin/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

**Checked on:** SecureTransport 5.5-20261029. Where the text says "tried", it was run on the lab, a test server of this version. A statement marked "not tried" comes from the API reference.

## What it changes, and for how long

Step 03 changes the **Sentinel settings of the server**, which are one set for the whole server, and the second scenario adds a **Fusion integration** to the server options. For the few
minutes between step 03 and the cleanup:

- The events of **every** transfer and login on the server, not only this use case's, are written to the overflow files, and **none reaches a real Sentinel, Workbench or Event Router**.
- If the server reports to one of them now, the settings are put back by step 99 (the copy of step 02) and read back to check they are the same. The Fusion options are put back and compared too.
  If a run stops half way, **run `99.cleanup_DELETE.sh`**.
- The copy is in `state.local.sentinel.json`, which git ignores. If it is lost, step 02 printed the host, the port and the overflow file; set them back by hand.
- The overflow policy is never changed. `ignore` (the default) stops collecting events when the file is full; `stop` would pause **every transfer of the server**. Do not use it on a server that works.
- A **fake HTTP server** runs on your machine for the time of the use case, and the SecureTransport server connects to it. It is stopped by the cleanup, by its process id, after the command of that
  process is checked: no other process is ever stopped.

Do not run it on a server that reports to a Sentinel you need, at a time when you need it. You also need `ST_CALLBACK_HOST` in `set_variables.local.sh`: the address of **this machine** as the
SecureTransport server reaches it (and, when 18081 is taken, `ST_CALLBACK_PORT`), and `python3` for the fake server.

## The idea

| Piece | What it is here |
| ----- | --------------- |
| The events | One for each state a transfer goes through (RECEIVING, RECEIVED, SENDING, SENT and more), the links between transfers (CycleLink), the route (XFBRouting) and each login (AUDIT). |
| Every state | Step 03 turns on **every state** the Sentinel settings can report: the ones that are off, and the ones the settings do not list yet, so everything the server can report is reported. |
| The receiver | Axway Sentinel, Workbench or Event Router: all take the same events, over the QLT protocol. None is needed here. |
| The unreachable receiver | `192.0.2.1`, port 1305. The address is reserved for documentation (RFC 5737) and nothing answers it. |
| The overflow file | The file the server writes the events to while it cannot send them. It is in the home folder of the account, so that the account can read it with the End User API. |
| One file for each scenario | The server writes to **one** overflow file at a time. The flow of a scenario runs with the overflow file turned to the **case file** of the scenario, and it is turned away again before the case file is read. |
| The reads file | `qlt_reads.dat`: where the overflow file points when no flow runs. Reading a case file is itself a transfer, with events (a login, a download); they go here, not into the case file. |
| The fake HTTP server | `fake_http_server.py`, on your machine. It stands in for "another server", and for Fusion. It is **not** a loop back to SecureTransport, so nothing it receives makes events of its own. |

## The two scenarios

| | `1-upload-push` | `2-upload-fusion-partner` |
| - | --------------- | ------------------------- |
| What happens | A user uploads a file. The server pushes it to another server. | A user uploads a file. Advanced Routing sends it to Fusion, and then to another server. |
| The route | one step: **Send To Partner** | two steps: **Send To Fusion**, then **Send To Partner** |
| The other server | a **Generic HTTP** site (type `http-generic`): `PUT /upload` on the fake server | the same site; Fusion is the fake server too: `POST /fusion` |
| What the fake server answers | 200 | to Fusion, 200 with the file it was sent (the file "Fusion sent back"); to the site, 200 |
| The case file | `qlt_1_upload_push.dat` | `qlt_2_upload_fusion_partner.dat` |
| Events in it (tried) | 15: two logins, the upload (RECEIVING, RECEIVED...), the push (TO_EXECUTE, SENDING, SENT...), two CycleLinks, XFBRouting | 20: the same, and the call to Fusion (a SENDING, a RECEIVING of its answer) and the second push |

"The server pushes to another server" is done here with **Advanced Routing** and a Send To Partner step. The other way tried, a subscription of a Basic application with a transfer configuration
`PARTNER-OUT` to a site, did not push on an upload (nothing was sent; the log shows the upload only).

## The steps

Run them in order, or run `00.run_all.sh`, which stops at the first step that fails and still runs the cleanup. The steps of a scenario are run **from its folder**.

| Step | Script | What it does | Risk |
| ---- | ------ | ------------ | ---- |
| 01 | `01.accounts_POST.sh` | Makes the account `example_qlt` with a generated password | write |
| 02 | `02.sentinel_GET.sh` | Writes down the Sentinel settings as they are (never overwrites the copy) | read |
| 03 | `03.sentinel_PATCH.sh [HOST] [PORT]` | Reports **every** state to the Sentinel that cannot be reached, with `qlt_reads.dat` as the overflow file | **config** |
| 04 | `04.fakeServer_start.sh` | Starts the fake HTTP server in the background | none |
| | **in each scenario folder** | | |
| 01 | `01.objects_POST.sh` | The site, the application, the subscription, the routes (and for scenario 2 the Fusion integration), and the folder | write / **config** |
| 02 | `02.flow_POST.sh` | Turns the overflow file to the case file, uploads, waits for the route, turns it away | write |
| 03 | `03.events_GET.sh [raw]` | Reads the case file and prints its events and what the fake server was sent; `raw` prints everything one event carries | read |
| 04 | `04.logsTransfers_GET.sh` | Ties the events to the transfers of the transfer log by their ids | read |
| 99 | `99.objects_DELETE.sh` | Deletes what step 01 made; scenario 2 puts the Fusion options back and compares them | write / **config** |
| 99 | `99.cleanup_DELETE.sh` | Runs the scenario cleanups, puts the settings back and checks them, stops the fake server, deletes the files and the account | config |

The transfers need the End User port: set `ST_ENDUSER_PORT` in `set_variables.local.sh` when it is not the admin port minus one.

## What you see

Step `03.events_GET.sh` of scenario 1 on the lab (the times and ids are different each time):

```
  TIME      EVENT         STATE / ACTION           DIR FILE / USER                                  COREID
  07:52:33  AUDIT         LOGIN_START                  example_qlt
  07:52:33  AUDIT         LOGIN_END                    example_qlt
  07:52:33  XFBTransfer   RECEIVING                R   push_1794289931.txt                          c742a6b7
  07:52:34  XFBTransfer   POST_PROC/ARCHIVED       R   push_1794289931.txt                          c742a6b7
  07:52:34  XFBTransfer   RECEIVED                 R   push_1794289931.txt                          c742a6b7
  07:52:35  XFBTransfer   POST_PROC                    push_1794289931.txt                          c742a6b7
  07:52:35  XFBTransfer   TO_EXECUTE               S   push_1794289931.txt                          c742a6b7
  07:52:35  CycleLink     XFBTransfer -> XFBTransfer     cycle XFyucT -> XFrgHg
  07:52:35  XFBTransfer   SENDING                  S   push_1794289931.txt                          c742a6b7
  07:52:36  XFBTransfer   SENT                     S   push_1794289931.txt                          c742a6b7
  ...
What the fake HTTP server was sent while the flow ran:

  07:52:35  PUT /upload  314 bytes  the file push_1794289931.txt  answered 200
```

The upload made the first events, the push the rest, and the CycleLink ties the two transfers together. Step `04.logsTransfers_GET.sh` shows the same ids in the transfer log: the **coreId** is the file's,
so the upload and the push of one file share it, and the **localId** (`id.mTransferStatusId` in the log) is the transfer's own.

## What the events are

Each event is an XML document, the one a Sentinel would have received:

```xml
<TrkDescriptor><TrkXML VERSION="1.0"/><TrkObject>
  <TrkIdentifier TYPE="Event" NAME="XFBTransfer" VERSION="1.0"/>
  <TrkAttr name="STATE" val="RECEIVED"/> <TrkAttr name="FILENAME" val="/home/example_qlt/qlt_push_in/push_1794289931.txt"/> <TrkAttr name="FILESIZE" val="47"/>
  <TrkAttr name="COREID" val="..."/> <TrkAttr name="LOCALID" val="..."/> <TrkAttr name="PROTOCOL" val="HTTP"/> ... about 90 attributes
</TrkObject></TrkDescriptor>
```

Four kinds were seen: `XFBTransfer` for a transfer, `XFBRouting` for the route, `CycleLink` (no name: its identifier has a lowercase `type`) for the link between a transfer and the one it started, and
`AUDIT` for a login (`LOGIN_START` and `LOGIN_END`, with the user, the address and the cipher). `03.events_GET.sh raw` prints every attribute of the RECEIVED event.

## What was tried

All of it on the lab, release 5.5-20261029, with a Sentinel and an overflow file that were already configured, which the use case put back and checked.

- **The server accepts a Sentinel it cannot reach.** The PATCH answers 204; the failure shows only as events going to the file, mostly within a second or two.
- **The overflow file can be turned while the server runs.** A PATCH of `overflowFilePath` takes effect at once, with no restart; what the server writes from then on goes to the new file, and the old one can be
  read. That is what keeps the scenarios apart: the case file of scenario 1 held only that flow (15 events), the one of scenario 2 only that one (20), and the events of reading them were in `qlt_reads.dat`.
- **The file is a circular buffer.** It starts with `Circular buffer file version 3.40.0-1` and four counters, then the events, each after a length and a colon, and the rest is padding. It is as large as the
  size setting (5 MB here), owned by root with mode 644, and the server makes it when it writes the first event, not when the settings change.
- **The records have no fixed separator.** Between two of them there is a line break, a carriage return, or nothing at all. Cut the file at the closing tag `</TrkDescriptor>`, not at the line breaks: cutting at
  the lines took two records that followed each other directly for one, and a SENT event seemed never to come.
- **The account can read the file, and delete it,** though the server made it: the folder is the account's.
- **Reading a case file makes events of its own** (two logins and a download). Because the overflow file is turned away before the reading, they go to the reads file and the case file stays clean.
- **The last events of a flow can come late.** In the Fusion flow a RECEIVED event arrived 6 seconds after the others. The flow waits 10 seconds after the route finishes before turning the file away.
- **A Generic HTTP site is what a fake server needs.** It sends the file with the method and to the path it is given (here `PUT /upload`, a multipart form with the file in a part). The plain HTTP site (`http`)
  logs in with `POST /`, asks with `HEAD` for the folder and the file, and expects a server of its own kind: it never uploaded to a server that answered what a web server answers.
- **Fusion is a set of server options.** `Fusion.Integrations.Registry` lists the names, and each name has `fusionEndpoint`, `authType` (BASIC or mTLS), `dataSent` (ALL, FILE, METADATA), `dataExpected`
  (PAYLOAD, RESPONSE), `username`, `password` and `verifyCertificate`. The Send To Fusion step names one (`fusionIntegrationName`). Removing a name from the registry deletes its options. With `dataSent` ALL the
  server posts a multipart form with the part `metadata.json` (the attributes of the transfer, the names the event carries) and the file; with `dataExpected` PAYLOAD the file the server answers is the file the
  next step sends. With RESPONSE only, the step hands no file on, and a Send To Partner after it, with the files of the step before it, finds none.
- **Turning every state on.** The lab already had all 37 states on. The path that turns them on was tried by switching off three first (`POST_PROC/ROUTED`, `LOGIN_START (AUDIT)` and `ACKED`): the patch addressed
  the one with a slash with `~1`, and all three were on afterwards.
- **A route that is deleted while it runs** leaves the file marked in-process by Advanced Routing: an upload of the same name is then refused (403). Each flow uploads a file named with the time, and waits for the
  route to finish before anything is deleted.

## Things to know

- **The home folder stays.** After the account is deleted its home folder stays on the server, and so does the archived copy of each upload under `/home/archives` (the file archiving of the server). The transfers
  stay in the transfer log.
- **A delete is a transfer too.** The cleanup deletes the files with the End User API, and the transfer log shows each delete under the file's coreId.
- **A server that never had a Sentinel set.** Once a host is set the settings refuse an empty one (400 "host must not be null or empty"), so step 99 turns reporting off, then clears the host and the overflow file
  with the options `AxwaySentinel.RemoteHost.host` and `AxwaySentinel.OverflowFile.path`. Tried with a copy made up to look like such a server: reporting off, host and path empty. The overflow size, the threshold and
  the states stay as step 03 left them, and the comparison leaves them out when the copy had none.
- **A server whose Fusion registry was empty** gets `[""]` back (an empty list is refused, 400). Not tried: the lab's registry had an entry.
- **The heartbeat is not touched.** The Sentinel settings say `heartbeatKind: heartbeat`, and the option behind it, `AxwaySentinel.Heartbeat.kind`, says `healthcheck`. The use case does not use it.
- **The fake server must be reachable.** `ST_CALLBACK_HOST` is the address of your machine as the SecureTransport server sees it. When the server cannot reach it the flow says so after two minutes
  ("Does the SecureTransport server reach ...?").
- **Why 192.0.2.1.** Any address a Sentinel is not at will do, given as the first parameter of step 03; a closed port on the server itself (`127.0.0.1`) should be refused at once instead of timing out (not tried).
  Do not give an address that is a real Sentinel.

## Not covered

- Sending to a real Sentinel, Workbench or Event Router, and reading the events there.
- The secure connection (`useSecureConnection`, `shouldVerifyCert`, FIPS) and the heartbeat of the settings, the `mappingRules`, and the asynchronous reporting and database queue settings
  (`asynchronousReporting*`, `databaseQueue*`, `connectionPoolSize`, `maxRetryCount`), which the server has in this release.
- Failed transfers (FAILED), a Fusion that answers with an error, and a partner that is not there.
- The overflow file filling up, the warning at the threshold, and the policy `stop`.

## The files

`lib.sh` and `scenario.sh` (sourced by the steps), `fake_http_server.py` (the fake server; its header says what it answers), and `state.local.*` (git ignores them: the password, the copy of the settings, the fake
server's process id and log, and for each scenario the ids of its objects, the events, the requests and the time window).
