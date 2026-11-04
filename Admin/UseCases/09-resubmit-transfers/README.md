# 09 Resubmit transfers

**Use case:** an administrator sends transfers through the server again: a route was broken and is fixed, a partner lost a file, a batch must be processed once more. **The same task
is done two ways**: with the Admin API 2.0, one transfer for each call, and with the Admin API 1.4, many transfers with one call. The two ways are in two folders, `2.0` and `1.4`,
that run on the same kind of data, so that you can compare them.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`Admin/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

**Checked on:** SecureTransport 5.5-20260924. Where the text says "tried", it was run on the lab, a test server of this version. A statement marked "not tried" comes from the API reference.
The API 1.4 is still served by 5.5; the part of it that 2.0 does not have is in [Admin/API 1.4](../../API%201.4/README.md).

## Which way

| | `2.0`: one at a time | `1.4`: one call |
| - | -------------------- | ---------------- |
| The call | `POST /api/v2.0/logs/transfers/{id}/operations?operation=resubmit`, once for each transfer | `POST /api/v1.4/transfers/resubmit`, once |
| How you choose the transfers | You read the list (`GET /logs/transfers`) and you choose each one yourself | By criteria in the same call: `accountOrLogin`, `file` (an exact name), `status`, `site`, `startTimeAfter`, `resubmitted` and more |
| The answer | One answer for each call: 200 or 400, with a message | One answer, 200, with a list: an entry for each transfer, `OK` or `ERROR` |
| The id of a transfer | `id.urlrepresentation` of the list | Not needed |
| If something is wrong | The one transfer is refused (400), the others go on | The call is 200 and the entry says `ERROR`: you must read the entries |
| The risk | A loop you wrote: it touches what the list showed | A criterion too wide touches everything. With nothing but `limit` it would resubmit **every transfer in the log** (not tried, on purpose) |
| Use it for | A few transfers, or when you must look at each | A batch that one criterion describes, such as everything of an account after a time |

Use the 2.0 way when you can. Use the 1.4 way for a batch, and **list the transfers with the same criteria first** (step `1.4/01`).

## What a resubmit is

A resubmit submits the stored file of a transfer to the server again. The original transfer stays in the log and is flagged `resubmitted: true`. The resubmit is **a new transfer**, with
`resubmitted: false`. Tried with three uploads of an account: after the resubmit, the log held six transfers, three flagged and three not.

Five points, all tried:

- **A resubmit needs what the transfer left behind.** The transfers of an account that had been deleted answered `ERROR` for each, "Error while resubmitting transfer", and the originals were flagged all the same. The answer gives no cause; the 1.4 reference names one for a single transfer, "Source for file does not exist".
- **Run it once for each batch.** `resubmitted=false` does not keep a second run away: the new transfers are transfers too, with `resubmitted: false`, and a second run resubmits them. (Tried with the 1.4 call: three transfers, two runs, nine in the log.)
- **Wait for Processed.** A transfer that is still `In Progress` cannot be resubmitted: the 2.0 call answers 400, and the 1.4 call an `ERROR` entry in its 200. The log shows a new transfer a second
  or two before it is done, so step `02` waits for the status `Processed`, not for the entry.
- **A failed transfer cannot be resubmitted.** `GET /logs/transfers/{id}` says `isResubmittable`, and the 2.0 call answers 400 for one that is not. A finished incoming transfer can.
- **In 1.4 the file criterion is an exact name.** `file=report_1.txt` finds the transfer, `file=report_*` finds nothing. And the call needs a `limit`: without one it answers 400 "Parameter limit should be a positive integer."

## The steps

`00.run_all.sh` runs everything and ends with `99.cleanup_DELETE.sh` (about 10 seconds). The scripts take their input as parameters, and say what they need when it is wrong, before any call.
The uploads use the End User API: set `ST_ENDUSER_PORT` in `set_variables.local.sh` when its port is not the admin port minus one.

| Step | What it does | Calls |
| ---- | ------------ | ----- |
| `01.accounts_POST` | Makes two user accounts, `example_rsb_a` (for 2.0) and `example_rsb_b` (for 1.4), with one generated password | `POST /accounts` |
| `02.uploads_POST` | Each account uploads three files; waits until the log shows six transfers as `Processed`; keeps the time it started | End User `POST /files`, `GET /logs/transfers` |
| `2.0/01.transfers_GET [ACCOUNT]` | Lists the transfers of the account; shows what the id looks like and what it is made of | `GET /logs/transfers` |
| `2.0/02.transfers_resubmit_POST [ACCOUNT]` | Reads the ones not resubmitted yet and resubmits each, one call each | `GET /logs/transfers`, `POST /logs/transfers/{id}/operations` |
| `2.0/03.check_GET [ACCOUNT]` | Shows the flagged originals and the new transfers | `GET /logs/transfers` |
| `1.4/01.transfers_GET [ACCOUNT]` | Lists what the bulk call would touch, with the same criteria | `GET /api/v1.4/transfers` |
| `1.4/02.transfers_resubmit_POST ACCOUNT` | Resubmits them with one call; reads the entries | `POST /api/v1.4/transfers/resubmit` |
| `1.4/03.check_GET [ACCOUNT]` | The same check, read with the 1.4 API | `GET /api/v1.4/transfers` |
| `99.cleanup_DELETE` | Deletes the two accounts. The transfers stay in the log | `DELETE /accounts/{name}` |

The scripts read the transfers **after the time of step 02**, so the transfers of an earlier run of the same accounts are never touched. The two accounts have fixed user ids: a home folder
outlives its account and keeps the id of its first owner.

## What stays after the cleanup

The transfers (and the resubmits) stay in the transfer log: no call deletes a log entry. The home folders stay on the server. A transfer of the deleted accounts can no longer be resubmitted: the call answers `ERROR`,
without a cause.

## What is not covered

- Resubmitting a **failed** transfer (refused), an **outbound** transfer to a partner site, or a transfer started by a **route**. The server decides what is resubmittable: read `isResubmittable`.
- Cancelling a transfer: that is the other `operation` of the same 2.0 call, in [`16.TransferLogs/04`](../../API%202.0/bash/16.TransferLogs/04.logs_transfers_id_operations_POST.sh).
- The other criteria of the 1.4 call (`status`, `site`, `protocol`, `direction`, `application`, `userClass`, `cycleId`, `actionBy`, `secure`, `operationIndex`, the time windows). Step `1.4/01` shows the
  call that previews them: use it before you use one.
