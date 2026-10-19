# 05 Checking transfers

**Use case:** see what became of the files: the list of the account's transfers, the filtered lists, one transfer in detail, and a summary.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`EndUser/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

Every upload and download is a transfer, and the server keeps its record. This use case only reads, so it creates nothing and
needs no cleanup beyond the session. Run `03-files-and-folders` or `04-larger-files` first to have some transfers to look at.
Pulling and pushing files to a partner site (`05.Transfers/03` to `06`) is not part of it: it needs a site an administrator has set up.

## The examples

Run them in order: each one builds on the one before it (and 03 needs one transfer to exist) (`00.run_all.sh` runs
them all, and ends with `99.cleanup_DELETE.sh`). Every script checks for an active session
first and logs in when there is none, so each can also be run on its own once what it needs is there.

| Script | What it does | Copied from (`EndUser/API 2.0/bash`) |
| ------ | ------------ | ------------------------------------ |
| `01.transfers_GET` | The latest transfers, one line each (`LIMIT`, default 5). | `05.Transfers/01.transfers_GET.sh` |
| `02.transfers_GET_filtered` | How many there are by direction, protocol, status and start time. | `05.Transfers/01.transfers_GET.sh` |
| `03.transfers_id_GET` | One transfer in detail, by its id. | `05.Transfers/02.transfers_id_GET.sh` |
| `04.transfers_summary` | Counts by status and direction, made with jq. | `05.Transfers/01.transfers_GET.sh` |
| `99.cleanup_DELETE` | Ends the session. Nothing was created. |  |

`lib.sh` is the one small file they share: it loads `../session.sh` (the settings, the
session helper `st_session`, and the cookie jar of this use case, `session.cookie.jar`, which git
ignores).

## What to take from it

- Filters go in the query, and one that takes several values (`status`) is repeated. A filter that finds nothing is an empty list, not an error.
- `startTimeAfter` takes a date in RFC 2822 form (what `date -R` prints): a plain date is refused with 400. The `date` options differ on macOS and Linux, so the script tries both.
- A `DELETE /files/...` shows up in the transfer list too, as an `Outgoing` transfer of type "User download" (confirmed 2026-10-19 with one upload and one delete): a delete is logged like a download, so the newest entries after a cleanup are deletes, not reads. An upload is `Incoming` / "User upload".
- The list and the single transfer name some fields differently (`filename` and `direction`, against `file` and `transferType`).
- A 403 on `/transfers` usually means the account may not use the transfers web service (`transfersWebServiceAllowed` in `GET /myself`; the administrator sets it).
- The server has no summary call: `group_by` on the list makes one (the list is at most 100 long).

## Tests

`tests/checks/test_bash_enduser_usecases.sh` runs every script against a stub `curl`.
`tests/integration/checks/63.enduser_usecases_scripts.py` runs them on a real server, as a
throwaway end user account it creates and removes, and checks that nothing is left behind.
