# 01 Authentication

**Use case:** get in to the end user API, and stay in, in the two ways it offers:
Basic authentication on every call, and a session.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`EndUser/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

## The idea

A call to the end user API has to prove who is asking. There are two ways:

1. **Basic authentication**: the user name and password go with the call itself.
   Nothing to set up and nothing to end, but the password is sent every time.
2. **A session**: the password is sent once, to log in. The server answers with a
   session cookie (and a `csrfToken`), and the next calls send the cookie instead.
   It ends when you log out, or when it expires.

## The examples

Run them in order: each one builds on the one before it (`00.run_all.sh` runs
them all, and ends with `99.cleanup_DELETE.sh`).

| Script | What it does | Copied from (`EndUser/API 2.0/bash`) |
| ------ | ------------ | ------------------------------------ |
| `01.basic_auth_GET_myself` | Who am I, with Basic authentication (`curl -u`) and no session. | `03.Myself/01.myself_GET.sh` |
| `02.no_credentials_GET_myself` | The same call with no credentials: refused with 401. | |
| `03.session_login_POST` | Log in: `POST /myself` checks the password once and returns a cookie, kept in a jar, and a `csrfToken`. | `01.Authenticate/01.myself_POST.sh` |
| `04.session_cookie_GET_myself` | Who am I, with the cookie only, no password. | `03.Myself/01.myself_GET.sh` |
| `05.session_csrf_header_GET_myself` | The same, sending the `csrfToken` header too, as a write should. | |
| `06.session_expired_recovery` | A session the server no longer knows gives 401 (or 403): log in again and carry on. The idea behind `ensure_session.sh`. | |
| `07.logout_DELETE` | Log out (`DELETE /myself`), then try the old cookie: 401, so it really ended. | `01.Authenticate/02.myself_DELETE.sh` |
| `99.cleanup_DELETE` | Ends a session still open and removes the jar and the token. | |

`lib.sh` is the one small file they share: it loads the settings and names the
files this use case keeps (`session.cookie.jar`, `state.local.csrf`, both ignored by git).
It does not touch `myCookie.jar` of the reference examples.

## What to take from it

- Basic authentication is the shortest way to one call. For many calls, log in once.
- A call with no credentials is refused with 401. A wrong password is not shown
  here on purpose: repeated failures can lock the account.
- The server asks for a `Referer` header on these calls; any text will do.
- Only 401 and 403 mean a lost session. A 500 or no answer is another problem,
  and a new login would not fix it.
- A logout that is not checked can look like it worked. Try the old cookie.
- The end user API has these two ways in and no others: its published API description (`/api/v2.0/docs/swagger.yaml` on the
  server) declares Basic authentication only, next to the session `POST /myself` gives, and no API key call or header is
  accepted (a made-up `SECURETRANSPORT-API-KEY` is a 401). API keys belong to the administration API, one per administrator
  (`Admin/UseCases/01-authentication`). So the rest of the end user examples use the session, from `01.Authenticate/01`.

## Tests

`tests/offline/checks/test_bash_enduser_usecases.sh` runs every script against a stub `curl`.
`tests/online/checks/62.enduser_usecase_authentication.py` runs them on a real
server, as a throwaway end user account it creates and removes.
