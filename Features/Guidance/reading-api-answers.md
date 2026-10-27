# Reading the answers of the SecureTransport REST APIs

**For:** anyone who writes a script or a program that calls the Admin API or the End User API.
**Checked on:** SecureTransport 5.5-20260924. Where the text says "tried", it was run on a lab server of this version, with throwaway accounts. A statement marked
"not tried" comes from the API reference, or from earlier work, and was not run for this guide.

## Summary

The status code is the first thing to read, and not the last. The two APIs answer in more than one way, and a script that reads only the code, or only one shape of
the body, will be wrong in some cases.

- **A `200` can carry a failure.** Operations on servers and daemons answer `200` and say in the body, in `isSuccessful`, whether they worked. The two operations
  use two different shapes.
- **An error has more than one shape.** The same code (`401`, `400`) can come as JSON, as plain text, or as HTML.
- **Lists are paged.** The Admin API tells you the size of the whole list (`totalCount`). The End User API does not.
- **`fields=` works on the Admin API only,** and refuses a few fields.
- **A new object's address is in the `Location` header,** not in the body.

The sections:

- [A 200 that says no](#a-200-that-says-no)
- [The shapes of an error](#the-shapes-of-an-error)
- [What happened, and what the API answers](#what-happened-and-what-the-api-answers)
- [Lists: counts and pages](#lists-counts-and-pages)
- [Fewer fields: `fields=`](#fewer-fields-fields)
- [Does it exist? `HEAD`](#does-it-exist-head)
- [A new object: the `Location` header](#a-new-object-the-location-header)
- [One call or a session](#one-call-or-a-session)
- [Checklist](#checklist)

The examples use `ST_SERVER`, `ST_PORT` (the Admin API), `ST_ENDUSER_PORT` (the End User API, 8443 on a standard install), `ST_USER` and `ST_PASSWORD`. Every call sends
a `Referer` header. (On the lab, a call without it was accepted too, for a read and for a write, on both APIs. Send it anyway: the protection that asks for it can be on.)

## A 200 that says no

These success codes are the usual ones:

| Call | Success |
| ---- | ------- |
| `POST` that creates | `201`, with a `Location` header and no body |
| `PATCH`, `PUT`, `DELETE` | `204`, no body |
| `GET`, `HEAD` | `200` |
| An operation (`POST .../operations?...`) | `200`, and the body says whether it worked |

Two operations answer `200` when they did **not** work. Tried, both safe:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/operations?serverName=no_such_server&operation=start" \
  -H "accept: application/json" -H "Referer: x"
```

```text
{
  "serverStatuses" : [ {
    "serverName" : "no_such_server",
    "message" : "Server with name no_such_server does not exist.",
    "isSuccessful" : false
  } ]
}
```

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/operations?operation=start&daemon=as2" \
  -H "accept: application/json" -H "Referer: x"
```

```text
[ {
  "daemon" : "AS2",
  "message" : "Can not start AS2 daemon - the default server As2 Default is not enabled. Enable the listener and perform the operation again.",
  "isSuccessful" : false
} ]
```

(The second call is safe on a server where the AS2 listener is off: it does not start anything. Do not start or stop a daemon on a server you do not own.)

The two answers have **different shapes**. The server operation answers an object with the list in `serverStatuses`. The daemon operation answers the list itself. The
reference describes the daemon answer as an object with the list in `daemonOperationResults`, so read both forms. In `jq`:

```bash
# every result that did not work, from either shape
jq -r '(if type == "array" then . else (.serverStatuses // .daemonOperationResults // []) end)[] | select(.isSuccessful != true) | "\(.serverName // .daemon): \(.message)"'
```

In Python:

```python
def results(answer):
    """The list of results of a server or daemon operation, whatever the shape of the answer."""
    if isinstance(answer, list):
        return answer
    return answer.get("serverStatuses") or answer.get("daemonOperationResults") or []


def unsuccessful(answer):
    """The results that are not `isSuccessful: true`. An answer with no result is not a success: nothing was said."""
    found = results(answer)
    if not found:
        return [{"message": "the answer has no result"}]
    return [r for r in found if r.get("isSuccessful") is not True]
```

Count an empty list as a failure: an operation that returns no result told you nothing.

## The shapes of an error

All of these were tried.

| Where | Code | Content-Type | Body |
| ----- | ---- | ------------ | ---- |
| Admin API, no credentials, or an unknown user | `401` | `text/html` | `Authentication required.` and a `WWW-Authenticate: Basic` header |
| End User API, no credentials | `401` | JSON | `{ "message":"Unauthorized", "url":"https://.../myself", "status":"401" }`: `status` is a **string** |
| End User API, an unknown user or a wrong password | `401` | `text/plain` | `Login failed. Re-submit your credentials.  If this problem persists, contact your system administrator.` |
| A request that is refused for what it holds (most `400`, `403`, `404`, `409`) | the code | JSON | `{ "message": "Error validating request", "validationErrors": [ "..." ], "docLink": "..." }` |
| End User API, a refusal with a code (a password reset with a bad token) | `401` | JSON | `{ "errors": [ { "code": "error.token.invalid", "detail": "Invalid token." } ] }` |
| End User API, an upload that failed (`500`) | `500` | JSON | `{ "message":"Error while uploading file to location: /dir_a", "url":"...", "status":"500" }` |
| Admin API, `POST /accounts` with a body that has no valid `type` | `400` | JSON (the header says so) | **Plain text:** `Invalid discriminator value. Check the schema for more information.` |
| A wrong method, `Accept` or `Content-Type` | `405`, `406`, `415` | JSON | `{ "message": "HTTP 405 Method Not Allowed" }`. A `405` has no `Allow` header. |

So an error can be JSON with `validationErrors`, JSON with `errors`, JSON with only `message`, plain text, or HTML. This function reads them all:

```python
import json


def error_messages(status, body):
    """The messages of an error answer, from whichever shape it has. [] when the answer is not an error."""
    if status < 400:
        return []
    try:
        data = json.loads(body)
    except ValueError:
        return [body.strip()]                      # plain text, or HTML: the text is the message
    if isinstance(data, dict):
        if data.get("validationErrors"):
            return [str(m) for m in data["validationErrors"]]
        if data.get("errors"):
            return ["%s: %s" % (e.get("code"), e.get("detail")) for e in data["errors"]]
        if data.get("message"):
            return [str(data["message"])]
    return [body.strip()]
```

Do not parse the body of an error as JSON without a guard, and do not look for one field only. Do not match on the text of a message either: the text is for people, and it can change in
a later release. Match on the code, and on `isSuccessful` where there is one.

## What happened, and what the API answers

The answers to common cases, tried with a throwaway account. Read the third column as what the API does today.

### Admin API

| What you did | Code | The body says |
| ------------ | ---- | ------------- |
| `GET` an account that does not exist | `404` | `validationErrors`: `Cannot find account with name ... or it is not accessible` |
| `HEAD` the same account | `404` | no body |
| Create an account whose name is taken | `409` | `Unable to create account '...': The account name is not unique.` |
| Start a daemon that is not one of the five | `400` | `Not correct daemon type: nope. Possible values are: ftp, http, ssh, pesit or as2.` |
| `POST /accounts` with a body that has no valid `type` | `400` | plain text: `Invalid discriminator value. Check the schema for more information.` |
| `POST` with `Content-Type: text/plain` | `415` | `HTTP 415 Unsupported Media Type` |
| Ask for `accept: text/csv` on a JSON resource | `406` | `HTTP 406 Not Acceptable` |
| `DELETE` on a resource that has no delete (`/version`) | `405` | `HTTP 405 Method Not Allowed` |
| `limit=-1` | `400` | `The limit should be a positive number or 0.` |
| `limit=abc` | `400` | `'limit' param is not a number` |
| `fields=nonsense` | `400` | `Field nonsense does not exist.` |
| An operation on a server that does not exist | `200` | `isSuccessful: false` (see above) |

### End User API

| What you did | Code | The body says |
| ------------ | ---- | ------------- |
| Upload with a `Content-MD5` that does not match the file | `500` | `Error while uploading file to location: /dir_a` |
| Rename a file that does not exist | `403` | `Unable to rename filePath: "/dir_a/absent.txt" to newFilePath: ...` |
| Delete a folder that is not empty | `403` | `Unable to delete directory: /dir_a. (directory is not empty)` |
| Create a folder that exists | `409` | `Error occurred while creating file: null` |
| `GET` a file that does not exist | `404` | `Error occurred while getting file size and type.` |
| Upload a file with a name that is already there | `201` | the file is replaced, and the `Location` header is the same |
| Share a folder that does not exist | `204` | nothing: no share was made, and the folder was not created |
| `PATCH` with `Content-Type: text/plain` | `415` | `HTTP 415 Unsupported Media Type` |
| `POST` on a resource that only has `GET` (`/secretQuestions`) | `405` | `HTTP 405 Method Not Allowed` |
| A wrong password, four times, then the right one | `401` | `Login failed. Re-submit your credentials.` The Admin API shows `user.locked` is `true`: the account is locked and the **right** password is refused too |

Three of these ask for care:

- A **wrong checksum is a `500`**, as a failure of the server would be. If your script retries on `500`, it will retry an upload that can never work. Compute the checksum before the
  upload, send the file again only when the checksum is right, and stop after a few tries.
- **Sharing a folder that does not exist answers `204`.** A `204` there does not prove that a share exists: look at the folder with `GET /files/<folder>?metadata=true`.
- **A locked account looks like a wrong password.** The answer does not say "locked", and waiting does not unlock it. Count your failed logins, and ask an administrator when the
  right password is refused.

## Lists: counts and pages

### The Admin API

An Admin list answers an object:

```text
{ "resultSet" : { "returnCount" : 5, "totalCount" : 19 }, "result" : [ ... ] }
```

- `totalCount` is the number of entries that match your filter, in all. `returnCount` is the number in this answer.
- **A page is 100 entries when you do not ask for more.** That is the setting `Webservices.EntriesPerPage` (100 on the lab). `limit=0` gives the same 100: it does not mean "all".
- Tried on the transfer log (23,706 entries): no `limit` gave 100, `limit=0` gave 100, `limit=1000` gave 1000. `limit=5000` did not answer within 30 seconds. Ask for pages of a few
  hundred, and walk them.
- `offset` is the number of entries to skip. An `offset` past the end gives an empty `result`, and `totalCount` stays the same.
- A filter changes `totalCount`: `GET /accounts?name=ZZTEST_ans*` gave 1 of 1, and a pattern that matches nothing gave 0 of 0. (Earlier work found that on some resources the
  total ignores the filter: check the one you use.)
- A `limit` that is not a number, or below 0, is a `400`.

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" \
  --data-urlencode "limit=5" --data-urlencode "offset=15" --data-urlencode "fields=name" -H "accept: application/json" -H "Referer: x"
```

On the lab, with 19 accounts, this returned 4 entries and `"totalCount" : 19`. This reads a whole list:

```python
def all_entries(get, path, params=None, page=500):
    """Every entry of an Admin list. get(path, params) returns the decoded answer of one call."""
    entries, offset = [], 0
    while True:
        answer = get(path, dict(params or {}, limit=page, offset=offset))
        got = answer["result"]
        entries.extend(got)
        if len(got) < page:                     # a short page is the last one
            return entries
        offset += page
```

Sort when the order matters (the transfer log has `sortByStartTime`), so that the pages do not move while you read. Count with the length of what you read. To only count,
ask for one entry and read `resultSet.totalCount`.

### The End User API

- **`GET /files` answers `{ "files": [ ... ], "self": { ... } }`.** There is no count. **Without `limit`, every entry is returned:** a folder with 105 entries returned 105. `limit` and `offset`
  work (`limit=10&offset=100` returned the last 5), and `sortBy` with `order` sort (tried: `sortBy=fileName&order=DESC`; the reference also lists `lastModifiedTime` and `size`, and `ASC`). **`limit=0` returned no entries.**
- **`GET /transfers` answers a plain list**, with no count and no wrapper. `limit` and `offset` work (with 3 transfers: `limit=2` gave 2, `offset=2` gave 1). How many entries a
  call returns when you give no `limit` was not tried beyond these.

Walk these lists as the Admin list: ask for a page, and stop when the page is shorter than the `limit`.

## Fewer fields: `fields=`

On the Admin API, `fields=name` narrows each entry to the fields you name (the `type` of the object is still there). Tried on `/accounts`:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" \
  --data-urlencode "limit=1" --data-urlencode "fields=name" -H "accept: application/json" -H "Referer: x"
```

```text
{ "resultSet" : { "returnCount" : 1, "totalCount" : 19 }, "result" : [ { "type" : "user", "name" : "anonymous" } ] }
```

- A field that does not exist is a `400`: `Field nonsense does not exist.`
- **The field that tells the kind of object cannot be named.** `fields=protocol` on `/servers` was refused with `Field protocol does not exist.`, although every server in the answer
  has `protocol`. Name the other fields, and read the kind from the answer.
- **The End User API has no `fields=`.** `GET /myself?fields=name` returned the whole account.

## Does it exist? `HEAD`

`HEAD` is the cheap question. It has no body, and the code is the answer: `200` it is there, `404` it is not. Tried on `/accounts/<name>` (`200` for an account, `404` for one that is not
there):

```bash
curl -s -k -I -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/john" -H "Referer: x"
```

Not every resource has a `HEAD` (earlier work found that denied users answers `405`): look at the code, and do not take a `405` for "not there".

## A new object: the `Location` header

A `POST` that creates answers `201` with **no body**. The address of the new object is in the `Location` header. Tried:

- Admin API, `POST /accounts`: `Location: https://host:port/api/v2.0/accounts/ZZTEST_ans_55k8`. The last part is the name of the account.
- End User API, an upload: `Location: https://host:8443/api/v2.0/files/%2Fdir_a%2Fa.txt` (the path is encoded). **A new folder** answered `201` with no `Location`.

To read it, ask curl for the headers:

```bash
curl -s -k -D - -o /dev/null -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" \
  -H "accept: application/json" -H "Content-Type: application/json" -H "Referer: x" \
  -d '{"name":"example_new","type":"user","uid":"1999","gid":"1999","homeFolder":"/home/example_new","user":{"name":"example_new","passwordCredentials":{"password":"a-long-Password-1"}}}'
```

Look for the line that starts with `Location:`. (This call creates the account `example_new`. Run it on a test server, and delete the account afterwards.) For some objects the last part of
the address is an id, not a name (routes, for example).

## One call or a session

Both APIs accept the user and the password on **every call** (`curl -u`). This is the simplest, and it is what the examples of this repository use.

A session is possible too. `POST /myself` with the user and the password is a **login**: it answers `200` with `{ "message" : "Logged in" }`, sets a cookie and returns a `csrfToken` header.
Later calls send the cookie. Tried on the End User API:

```bash
curl -s -k -i -c cookies.txt -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_ENDUSER_PORT}/api/v2.0/myself" \
  -H "accept: application/json" -H "Referer: x"
```

```text
HTTP/1.1 200 OK
Set-Cookie: FDX=...; Path=/; Secure; HttpOnly; SameSite=Strict
csrfToken: b63SYdaLB7UlREUnPcHguSq4JqLOhTfk
{ "message" : "Logged in" }
```

```bash
curl -s -k -b cookies.txt "https://${ST_SERVER}:${ST_ENDUSER_PORT}/api/v2.0/myself" -H "accept: application/json" -H "Referer: x"
```

The call with the cookie answers `200`. The same call with no cookie and no password answers `401`. `POST /myself` does not return the account: `GET /myself` does.

A wrong password counts. Four wrong passwords locked the throwaway account on the lab, and then the right password was refused too (see above). When a script logs in again and again, give it
a password that is right and stop at the first `401`.

## Checklist

- [ ] After an operation on a server or a daemon, read `isSuccessful` of each result, from both shapes (a list, or an object with a list in it). An empty answer is not a success.
- [ ] An error may be JSON with `validationErrors`, JSON with `errors`, JSON with `message`, plain text or HTML. Read the body with a guard.
- [ ] Do not retry a `500` on an upload without checking the checksum first.
- [ ] A `204` for a share does not prove that the folder exists.
- [ ] A count is `resultSet.totalCount` on the Admin API. The End User API has none: walk to a short page.
- [ ] Ask for the page size you want. `limit=0` is not "all" on the Admin API, and it returns nothing on `GET /files`.
- [ ] Keep a page to a few hundred entries.
- [ ] Do not name `protocol` or `type` in `fields=`. Do not use `fields=` on the End User API.
- [ ] The address of a new object is in `Location`, not in the body.
- [ ] Count failed logins. A locked account answers like a wrong password.

## What was not checked

- `HEAD` on resources other than accounts. (Earlier work found a `405` on denied users.)
- The number of entries `GET /transfers` (End User API) returns when no `limit` is given: the account had 3 transfers.
- The sporadic `500` on a correct upload. It was seen now and then on the lab, and not made to happen on demand.
- Whether the missing `Referer` header is accepted when the protection that asks for it is switched on in a way other than on the lab.
- The details of sessions and the `csrfToken` header: see the guide on authentication and sessions.
