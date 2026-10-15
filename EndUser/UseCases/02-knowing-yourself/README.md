# 02 Knowing yourself

**Use case:** find out what the server says about the account you are, and shape the answer: the whole object, a few values, whether the password has expired, the server's clock and the address book.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`EndUser/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

The answers of the end user API are JSON, and mostly bigger than what a script needs. This use case reads
`/myself` and the calls around it, and narrows each answer with `jq`, on your side, because the server does not do it.

## The examples

Run them in order: each one builds on the one before it (`00.run_all.sh` runs
them all, and ends with `99.cleanup_DELETE.sh`). Every script checks for an active session
first and logs in when there is none, so each can also be run on its own once what it needs is there.

| Script | What it does | Copied from (`EndUser/API 2.0/bash`) |
| ------ | ------------ | ------------------------------------ |
| `01.myself_GET` | Who am I: the whole object. | `03.Myself/01.myself_GET.sh` |
| `02.myself_GET_narrowed` | The same answer narrowed with jq: one value, a few, a default for a null, the field names. Shows that `?fields=` is ignored. | `03.Myself/01.myself_GET.sh` |
| `03.myself_passwordExpired_GET` | Has the password expired? Exit 0 when not, 3 when it has. | `03.Myself/02.myself_passwordExpired_GET.sh` |
| `04.serverTime_GET` | The server's clock, next to yours. | `06.ServerTime/01.serverTime_GET.sh` |
| `05.myself_addressBook_GET` | The address book, counted by type and narrowed to the users with an e-mail. | `03.Myself/08.myself_addressBook_GET.sh` |
| `99.cleanup_DELETE` | Ends the session and removes the jar. Nothing was created on the server. |  |

`lib.sh` is the one small file they share: it loads `../session.sh` (the settings, the
session helper `st_session`, and the cookie jar of this use case, `session.cookie.jar`, which git
ignores).

## What to take from it

- `/myself` ignores a `fields=` query: it sends every field, so narrow with `jq` (`jq -r` prints a text value without quotes).
- A field the account has no value for is `null`: `// "none"` in `jq` gives a readable default.
- `/myself/passwordExpired` has a fixed message in the answer whether or not the password has expired: read the `expired` field.
- Exit codes carry meaning: 3 is "the password has expired", 1 is a failure, so a caller can tell them apart.

## Tests

`tests/checks/test_bash_enduser_usecases.sh` runs every script against a stub `curl`.
`tests/integration/checks/63.enduser_usecases_scripts.py` runs them on a real server, as a
throwaway end user account it creates and removes, and checks that nothing is left behind.
