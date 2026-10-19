# 01 Authentication

**Use case:** get in to the administration API, and stay in, in the three ways it offers: Basic authentication on every call, a session, and an API key.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`Admin/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

A call to the administration API has to prove who is asking. Either the name and password go with the call itself
(Basic authentication, nothing to set up, the password sent every time), or they are sent once, to log in, and the
server answers with a session cookie and a `csrfToken` that the next calls send back. The difference from the end user
API is the token: a write inside a session should carry it as a `csrfToken` header. The third way is an **API key**:
made once for an administrator, it authenticates every request on its own in the `SECURETRANSPORT-API-KEY` header, with
no password, no session and no token, which is what a script or an integration wants. The end user API has no API keys.

## The examples

Run them in order: each one builds on the one before it (`00.run_all.sh` runs
them all, and ends with `99.cleanup_DELETE.sh`). The scripts of `02` check for an active session
first and log in when there is none, so each can also be run on its own.

| Script | What it does | Copied from (`Admin/API 2.0/bash`) |
| ------ | ------------ | ---------------------------------- |
| `01.basic_auth_GET_myself` | Who am I, with Basic authentication (`curl -u`) and no session. | `02.Introduction/03.myself_GET.sh` |
| `02.no_credentials_GET_myself` | The same call with no credentials: refused with 401. |  |
| `03.session_login_POST` | Log in: `POST /myself` checks the password once and returns a cookie, kept in a jar, and a `csrfToken`. | `01.Authentication/01.myself_cookie_POST.sh` |
| `04.session_cookie_GET_myself` | Who am I, with the cookie only, no password. | `02.Introduction/03.myself_GET.sh` |
| `05.session_csrf_header_PATCH_myself` | A write in the session with the `csrfToken` header. It patches `/myself` with the value it already has, so nothing changes. Also asks the server whether it enforces the token. | `02.Introduction/04.myself_PATCH.sh` |
| `06.session_expired_recovery` | A session the server no longer knows gives 401 (or 403): log in again and carry on. |  |
| `07.logout_DELETE` | Log out (`DELETE /myself`, cookie and token), then try the old cookie: 401, so it really ended. | `02.Introduction/06.myself_DELETE.sh` |
| `08.apikey_POST` | Make an API key for the administrator: 1 day, read only. It is saved in a file git ignores; the server keeps only a hash. | `21.Administrators/08.administrators_name_apiKeys_POST.sh` |
| `09.apikey_GET_myself` | Who am I, with the key alone: no user, no password, no cookie, no token. Then a write with the read-only key: refused, 403. | `21.Administrators/09.administrators_name_apiKeys_GET.sh` |
| `10.apikey_DELETE` | Revoke that key by its id, and show that it is refused afterwards (401). | `21.Administrators/10.administrators_name_apiKeys_keyId_DELETE.sh` |
| `99.cleanup_DELETE` | Ends a session still open, revokes the use case's API key if one is left (by its id), and removes the jar and the state files. Nothing else was created on the server. |  |

`lib.sh` is the one small file they share: it loads `../session.sh` (the settings, `ST_URL`, the cookie
jar of this use case, `session.cookie.jar`, which git ignores, and the session helper `st_session`).

## What to take from it

- Basic authentication is the shortest way to one call, and a call that carries its own credentials needs no token even for a write. It works because `Webservices.Admin.BasicAuthEnabled` is true (05 shows the neighbouring option).
- Since the 20230525 release `Webservices.Admin.CsrfToken.enabled` is true by default: `POST /myself` returns a `csrfToken` response header and a write in the session has to send it back. The lab accepts a write without it, and even with a wrong one, so a script that leaves it out works there and fails on a server that enforces it: send it.
- `POST /myself` is a login, not a way to read the account: its answer is `{"message": "Logged in"}`. Use `GET /myself` for the account.
- A call with no credentials is 401. A wrong password is not shown here on purpose: repeated failures can lock the administrator.
- Only 401 and 403 mean a lost session. A 500 or no answer is another problem, and a new login would not fix it.
- A logout that is not checked can look like it worked. Try the old cookie.
- An API key is the way in for automation: no login to expire, no password in the script. It is a secret like one: it is shown once, the
  server keeps only a hash, it has a mandatory expiry and permissions (`read` is GET and HEAD, `write` POST, PUT and PATCH, `delete`
  DELETE), and an administrator holds at most 2. A method it does not cover is a plain-text 403, a revoked or unknown key a plain-text 401.
- Making a key needs credentials (a key cannot make its own), and one key of the lab administrator was already there: the steps
  work only on the key they made, by its id.

## Tests

`tests/checks/test_bash_admin_usecases.sh` runs every script against a stub `curl`.
`tests/integration/checks/64.admin_usecases_scripts.py` runs them on a real server and checks that the administrator's own
settings are exactly as they were afterwards.
