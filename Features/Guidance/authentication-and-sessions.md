# Authentication and sessions in the SecureTransport REST API

**For:** administrators and integrators who write scripts or programs against the Admin API or the End User API.
**Checked on:** SecureTransport 5.5-20260924. Where the text says "the server does", it was tried on this version only. A statement marked "not tried"
comes from the API reference or from earlier notes and was not run again. In this guide, "the lab" is the test server that it was checked on.

## Summary

There are three ways to prove who you are. Basic authentication works on both APIs. A session (a login that gives a cookie) works on both. An API key works
on the Admin API only. This guide shows each one with a command you can run. Then it covers what can surprise you. These are what a session remembers, what an
ended session answers, and what a locked account answers. The last is what a forced secret-question change does to your calls. It ends with advice on which way to use
in which case. The advice is not a statement about the product.

- [The three ways in](#the-three-ways-in)
- [Basic authentication](#basic-authentication)
- [A session](#a-session)
- [The Referer header](#the-referer-header)
- [API keys (Admin API only)](#api-keys-admin-api-only)
- [What a session remembers](#what-a-session-remembers)
- [An ended or expired session](#an-ended-or-expired-session)
- [A locked account](#a-locked-account)
- [A forced change of the secret question](#a-forced-change-of-the-secret-question)
- [What the server does with the CSRF token](#what-the-server-does-with-the-csrf-token)
- [Advice](#advice)

## The three ways in

| Way | Admin API | End User API | What you send | Needs a login call |
| --- | --------- | ------------ | ------------- | ------------------ |
| **Basic authentication** | Yes | Yes | The login name and password on every call (`curl -u user:password`) | No |
| **A session** | Yes | Yes | The cookie from the login, and the `csrfToken` header on a write | Yes: `POST /myself` |
| **An API key** | Yes | **No** | The header `SECURETRANSPORT-API-KEY: <key>` on every call | No, but the key must be made first |

The End User reference has one security scheme, `basicAuthScheme`. A call to the End User API with an API key header was refused with 401 (tried).

The Admin API uses port `${ST_PORT}` (444 on the lab). The End User API has its own port. Look at your server's configuration: it is often the Admin port minus one,
but not always. The examples below use `${ST_ENDUSER_PORT:-8443}`.

## Basic authentication

Every call carries the login name and the password. There is no login and no logout, and no token to keep. It works on both APIs.

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" \
  -H "accept: application/json" -H "Referer: x"
```

The answer is 200 with your own account. A call with no credentials is refused with 401 (tried).

On the lab, a write with only Basic authentication works. No cookie and no token are needed. Tried: a `PATCH` of `/myself` to its own value answered 204.

## A session

A session saves you from sending the password on every call. You log in once, keep the cookie, and log out at the end.

**1. Log in.** `POST /myself` with Basic authentication. Keep the cookie (`-c`) and the response headers (`-D`):

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" \
  -c session.jar -D session.headers -H "accept: application/json" -H "Referer: x"
```

```text
{
  "message" : "Logged in"
}
```

`POST /myself` is a login call. It does not give you your account. The answer is only `Logged in`, and the answer has a `csrfToken` header (tried on both APIs).
To read your own account, use `GET /myself`.

**2. Use the cookie.** No password now:

```bash
curl -s -k -b session.jar "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "Referer: x"
```

**3. Send the token on a write.** Read it from the login's headers once, and send it on every `POST`, `PUT`, `PATCH` and `DELETE`:

```bash
TOKEN=$(tr -d '\r' < session.headers | sed -n 's/^[Cc][Ss][Rr][Ff][Tt]oken: *//p')
curl -s -k -b session.jar -X PATCH "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" \
  -H "csrfToken: ${TOKEN}" -H "Content-Type: application/json" -H "Referer: x" -d '[]'
```

**4. Log out with the cookie.** Not with a password:

```bash
curl -s -k -b session.jar -X DELETE "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "csrfToken: ${TOKEN}" -H "Referer: x"
```

The answer is 200. The same cookie is refused with 401 afterwards (tried). `DELETE /myself` with Basic authentication also answers 200. It logs a new session
in and out, so the session in your cookie jar stays open (reported in earlier notes, not tried again).

The End User API works the same way. Use its own port: `https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/myself`.

## The Referer header

Send a `Referer` header on every call, with the same text for the whole session. It is part of the contract of the API. The lab accepted calls without it, both reads
and writes (tried: a `GET` and a `PATCH` answered 200 and 204). A server that enforces it can refuse the same call. Write the script for the contract, not for the
lab.

## API keys (Admin API only)

An API key is for automation. It has no session and no cookie. The key is made for one administrator.

| Rule | Value |
| ---- | ----- |
| Where | Admin API only: `POST /administrators/{name}/api-keys` |
| Header on every call | `SECURETRANSPORT-API-KEY: <key>` |
| How many | At most 2 keys for one administrator. A third is refused with 409 "Maximum number of API keys reached". |
| Expiry | Always. Give `validityDays` (a whole number) or `expiresAt` (RFC 2822), never both and never none. Both cases are refused with 400. `expiresAt` alone was accepted (201). |
| Permissions | `read`, `write`, `delete`. `write` covers `POST`, `PUT` and `PATCH`. |
| Who can make one | A caller with credentials (Basic authentication). A key cannot make a key: it was refused with 403 (tried). |
| The key itself | Shown once, in the answer to the creation. The server keeps a hash only. |

Make a key that can only read, and is valid for one day:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators/example_admin/api-keys" \
  -H "Content-Type: application/json" -H "accept: application/json" -H "Referer: x" -d '{"validityDays": 1, "permissions": ["read"]}'
```

```text
{
  "id" : "8a050087a0e7255001a17bcb82e60d60",
  "expiresAt" : "Wed, 28 Oct 2026 07:18:17 +0200",
  "createdAt" : "Tue, 27 Oct 2026 07:18:17 +0200",
  "expired" : false,
  "permissions" : [ "read" ],
  "key" : "54b6e5..."
}
```

Use it:

```bash
curl -s -k -H "SECURETRANSPORT-API-KEY: ${API_KEY}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "Referer: x"
```

The answer is 200, with the account of the administrator that owns the key, and `apiKeyPermissions` in it. With the read-only key above:

- a `PATCH` was refused with 403;
- a wrong key was refused with 401.

Revoke a key by its id: `DELETE /administrators/{name}/api-keys/{id}` (answer 204). Revoke the old key before you make a third one. The shipped use case
`Admin/UseCases/01-authentication` (steps 08 to 10) makes, uses and revokes a key.

## What a session remembers

A session keeps what the server knew when you logged in. If something changes on the account later, the open session does not see it. Example, tried with the End User API:

1. An account has no email address. `GET /myself` says `"sharingAllowed": false`.
2. An administrator adds the email address (`PATCH /accounts/{name}`, answer 204).
3. In the same session, `GET /myself` still says `false`.
4. After a new login, it says `true`.

When an administrator changes an account and a script keeps a long session, log in again before you rely on the change.

## An ended or expired session

A cookie that the server no longer accepts is answered with **401**. This happens after a logout, after a timeout, or after the password changes (not tried again for
the last one). A script that keeps a session should check it first, and log in again on 401 or 403. Any other answer (the server is unreachable, a 500) is not a lost
session: let the real call report it.

```bash
EU="https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0"
JAR=session.jar
ensure_session() {
  code=$(curl -s -k -o /dev/null -w '%{http_code}' -b "${JAR}" -H "Referer: x" "${EU}/myself")
  case "${code}" in
    401|403) curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST -c "${JAR}" -o /dev/null -H "Referer: x" "${EU}/myself" ;;
  esac
}
ensure_session
```

The End User examples of this repository do this: `EndUser/API 2.0/bash/ensure_session.sh`.

## A locked account

An account is locked after the maximum number of wrong passwords (the setting `failedAuthMaximum`, which was 3 when this lab was last read). The Admin API then shows
`user.locked: true`. Tried with an End User account:

- Five wrong passwords: 401 each time.
- Then the **right** password: 401, with the same text as for a wrong one: `Login failed. Re-submit your credentials. If this problem persists, contact your system
  administrator.` The answer does not say that the account is locked.
- Time does not release it. An administrator does: `PATCH /accounts/{name}` with `[{"op": "replace", "path": "/user/locked", "value": false}]` answered 204,
  and the right password worked again.

If a script gets 401 with a password it knows is right, look at `user.locked` before you change anything else. A test that fails a login on purpose should use an account
of its own and count its attempts.

## A forced change of the secret question

An administrator can make an account set a new secret question: `PATCH /accounts/{name}` with `replace` of `/user/secretQuestion/forceSecretQuestionChange` to
`true` (the shipped example `Admin/API 2.0/bash/05.Accounts/06.accounts_name_PATCH_secretQuestion.sh`). While it is true, nearly every End User call answers **403**
with `error.secretQuestion.required` ("You have to set a new secret question."). Tried, with Basic authentication:

| Call | Answer |
| ---- | ------ |
| `POST /myself` (the login) | 403 `error.secretQuestion.required` |
| `GET /myself` | 403 `error.secretQuestion.required` |
| `GET /files` | 403 `error.secretQuestion.required` |
| `GET /secretQuestions` | 200 (the list of questions on offer) |
| `DELETE /myself` | 200 |
| `PUT /myself/secretQuestion` with the password, a question from the list and an answer | 204, and it lifts the block |

After the `PUT`, `GET /myself` answered 200 again. You cannot log in before you set the new question. A script that gets 403 `error.secretQuestion.required` has to
use Basic authentication for these three calls.

The service has a switch, the server option `Users.SecretQuestion.Enabled` (it was on during this check, and was tried both ways earlier on the same lab). With the
service **on**, `GET /secretQuestions` answers 200. With it **off**, `GET /secretQuestions` and `GET /myself/secretQuestion` answer 503 `error.secretQuestion.serviceDisabled`.
With it on, `GET /myself/secretQuestion` also answers 503 for an account that has no question yet, so only `GET /secretQuestions` tells the two cases apart.

## What the server does with the CSRF token

CSRF means cross-site request forgery: the token protects against it. The Admin option `Webservices.Admin.CsrfToken.enabled` was `true` on the lab. The login answer has a `csrfToken` header, and the reference asks you to send it back on every
write in a session. **What the lab does today:** a write in a session was accepted with the right token, with a wrong token (`csrfToken: nope`) and with none. This was
true for the Admin API (a `PATCH` of `/myself`, 204) and for the End User API (creating a folder, 201). A GET needs no token.

So a script that leaves the token out works on this lab. It can fail on a server that enforces it. **Send the token anyway.** Read it once from the login and send it on
every write, as the session example above does. A call that carries Basic authentication on its own (no cookie) needs no token.

## Advice

This part is advice. It is not product behaviour, and your own rules for secrets come first.

| Case | A good fit | Why |
| ---- | ---------- | --- |
| A script that makes a few calls from a place you control | Basic authentication over TLS, with the password held in a vault or a protected variable | No login to lose, no token to keep, nothing to log out |
| A job that makes many calls in a row | A session: log in once, keep the cookie, send the token, log out | The password goes over the network once |
| Automation for an administrator, with no person in it | An API key with only the permissions it needs, and a short expiry (days, not years). Keep at most 2, and revoke the old one when you make a new one. | A leaked key is limited in what it can do and in time, and it is not the password |
| An end user's own script | Basic authentication or a session. An API key does not work here. | The End User API has no API key |

Always send the `Referer` header. Never put the password or a key in a script that you share. A `.gitignore` entry is not a vault.

## Checklist

- [ ] Every call sends the `Referer` header.
- [ ] A session sends the `csrfToken` on every write, and logs out with the cookie.
- [ ] A script that keeps a session logs in again on 401 or 403.
- [ ] A 401 with a right password makes the script look at `user.locked`.
- [ ] A 403 `error.secretQuestion.required` is handled with Basic authentication.
- [ ] An API key has the least permissions it needs, an expiry, and a plan for revoking it.
