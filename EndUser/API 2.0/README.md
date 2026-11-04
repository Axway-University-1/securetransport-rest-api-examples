# End User API 2.0 examples

> **For test environments only.** Read the [Disclaimer](../../README.md#disclaimer) before you run anything. The settings
> (`ST_SERVER`, `ST_PORT`, `ST_USER`, `ST_PASSWORD`) are explained in [Configuration](../../README.md#configuration). The End User
> API is on its own port, 8443 (443 on a root install), not the administrator's.

The examples for the user level API: `bash/`, one example for each call. For a task done step by step, with a script for each step,
see the [End User use cases](../UseCases/README.md). What the older End User API 1.4 does and this one does not (the mailbox) is in [EndUser/API 1.4](../API%201.4/README.md).

## What is covered

| Topic | Endpoints | bash |
| ----- | --------- | :--: |
| 01. Authenticate | `/myself`, login and logout | 2 |
| 02. Files | `/files` and `/fileOperations`: list, with paging, sorting, metadata and glob patterns; create a folder; upload, with an MD5 check; download; rename; share and unshare; delete | 15 |
| 03. Myself | `/myself`, `/myself/password`, `/myself/passwordExpired`, `/myself/secretQuestion`, `/myself/addressBook`: the account, password change and reset, the account's own secret question, the address book | 9 |
| 04. File Operations | `/fileOperations`: MD5 checksum, an operation's state, chunked and multipart uploads, cancel | 5 |
| 05. Transfers | `/transfers`, `/transfers/operations`, `/transfers/pullSummary`: the user's transfer log, pull, push, folder monitor, pull summary, AS2 receipt check | 7 |
| 06. Server Time | `/serverTime` | 1 |
| 07. Secret Questions | `/secretQuestions`: the questions the server offers, a check that one is on the list, the Nth question for a script | 3 |

The EndUser examples are bash only, with no bat twins. Every resource of the EndUser API 2.0 reference has an example. All of them
were run against a real server except three, which say so in their own header:
the password reset pair (`03.Myself/04` and `05`), which need a real reset
email, and `05.Transfers/07`, which needs an AS2 transfer.

Where the EndUser API behaves differently from what you might expect,
confirmed against a real server:

- **Writes do not need the `csrfToken`.** The login answers with one, but a
  POST, PUT, PATCH or DELETE succeeds without it: the session cookie is enough.
- **Changing the password ends the session.** The next call with the same
  cookie answers 401. Log in again with the new password, as
  `bash/03.Myself/03.myself_password_POST_change.sh` does.
- **`/transfers` returns a plain list**, not the `{resultSet, result}` envelope
  the Admin API uses. So do `/myself/addressBook` and `/secretQuestions`.
- **A wrong `Content-MD5` gives a bare 500**, "Error while uploading file", with
  no word about the checksum. File Tracking logs the upload as Failed.
- **A file operation's status describes the operation, not the file.** An
  Upload stays `IN_PROGRESS` after its last chunk, though the file is whole.
  Check the file itself, with `bash/02.Files/10.files_filepath_GET_metadata.sh`.
- **`/serverTime` writes the offset as `+0300`**, not with the `Z` the API
  reference shows. Parse the offset, as `bash/06.ServerTime/01.serverTime_GET.sh` does.
