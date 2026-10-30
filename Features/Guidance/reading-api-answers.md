# Reading the answers of the SecureTransport REST APIs

**For:** anyone who writes a script or a program that calls the Admin API or the End User API.
**Checked on:** SecureTransport 5.5-20260924. Where the text says "tried", it was run on a lab server of this version, with throwaway objects. In this guide, "the lab" is the test server that it was checked on.

## Summary

The status code is the first thing to read, and not the last. The two APIs answer in more than one way. A script that reads only the code, or only one shape of
the body, will be wrong in some cases.

- **A `200` can carry a failure.** Operations on servers and daemons answer `200` and say in the body, in `isSuccessful`, whether they worked. The two operations use two different shapes.
- **An error has more than one shape.** The same code (`401`, `400`) can come as JSON, as plain text, or as HTML.
- **The rest is in the use cases.** Each case is a script you can run. Lists, paging and `fields=`: [Admin](../../Admin/UseCases/06-lists-paging-and-fields/README.md) and
  [End User](../../EndUser/UseCases/08-lists-and-paging/README.md). Stopping and starting a daemon: [Admin](../../Admin/UseCases/04-stopping-and-starting-servers/README.md).
  Changing an object: [Admin](../../Admin/UseCases/05-changing-an-object/README.md). Moving files: [End User](../../EndUser/UseCases/README.md). Sessions are in
  [Authentication and sessions](authentication-and-sessions.md).

The examples use `ST_SERVER`, `ST_PORT` (the Admin API), `ST_USER` and `ST_PASSWORD`. Every call sends a `Referer` header.

## A 200 that says no

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
{ "serverStatuses" : [ { "serverName" : "no_such_server", "message" : "Server with name no_such_server does not exist.", "isSuccessful" : false } ] }
```

A daemon operation answers the list itself, `[ { "daemon" : "AS2", "message" : "...", "isSuccessful" : false } ]`. The reference describes an object with the list in
`daemonOperationResults`, so read both forms. In `jq`, print every result that did not work:

```bash
jq -r '(if type == "array" then . else (.serverStatuses // .daemonOperationResults // []) end)[] | select(.isSuccessful != true) | "\(.serverName // .daemon): \(.message)"'
```

In Python, an answer with no result is a failure: an operation that returns nothing told you nothing.

```python
def unsuccessful(answer):
    """The results that are not `isSuccessful: true`, from either shape of answer."""
    found = answer if isinstance(answer, list) else (answer.get("serverStatuses") or answer.get("daemonOperationResults") or [])
    if not found:
        return [{"message": "the answer has no result"}]
    return [r for r in found if r.get("isSuccessful") is not True]
```

## The shapes of an error

All of these were tried.

| Where | Code | Content-Type | Body |
| ----- | ---- | ------------ | ---- |
| Admin API, no credentials, or an unknown user | `401` | `text/html` | `Authentication required.` and a `WWW-Authenticate: Basic` header |
| End User API, no credentials | `401` | JSON | `{ "message":"Unauthorized", "url":"https://.../myself", "status":"401" }`: `status` is a **string** |
| End User API, an unknown user or a wrong password | `401` | `text/plain` | `Login failed. Re-submit your credentials.  If this problem persists, contact your system administrator.` |
| A request that is refused for what it holds (most `400`, `403`, `404`, `409`) | the code | JSON | `{ "message": "Error validating request", "validationErrors": [ "..." ], "docLink": "..." }` |
| End User API, a refusal with a code (a password reset with a bad token) | `401` | JSON | `{ "errors": [ { "code": "error.token.invalid", "detail": "Invalid token." } ] }` |
| End User API, an upload that failed | `500` | JSON | `{ "message":"Error while uploading file to location: /dir_a", "url":"...", "status":"500" }` |
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

## Checklist

- [ ] After an operation on a server or a daemon, read `isSuccessful` of each result. The answer is a list, or an object with a list in it. An empty answer is not a success.
- [ ] An error may be JSON with `validationErrors`, JSON with `errors`, JSON with `message`, plain text or HTML. Read the body with a guard.
- [ ] Match on the code and on `isSuccessful`, not on the text of a message.
- [ ] Do not retry a `500` on an upload without checking the file and its checksum first (see the End User use case on larger files).
- [ ] For lists, the use cases say which API has a count, which has `fields=`, and what `limit=0` means.
