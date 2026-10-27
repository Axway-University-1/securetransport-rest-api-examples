# Field names and shapes that differ between releases and between API areas

**For:** integrators and administrators who write clients for the Admin API and the End User API, and who run them against more than one release.
**Checked on:** SecureTransport 5.5-20260924. Only this release was available, so a statement about another release is marked "reported, not tried on this release".
Everything else was run on the lab. In this guide, "the lab" is the test server that it was checked on.

## Summary

The same thing can have two names. This happens inside one release, between the Admin API and the End User API, and between a list and a single object. It also
happens between releases: names and defaults have changed. A client that hard-codes one name works on the server it was written on, and fails with an empty value, not an error, on another.
This guide lists the differences that were found and shows each one. It ends with four habits: look the field up, read the version, ask for
fields and fall back, and keep your release's reference open.

- [Between releases](#between-releases)
- [The same thing, two names](#the-same-thing-two-names)
- [Two shapes for a list](#two-shapes-for-a-list)
- [Names that are returned but cannot be asked for](#names-that-are-returned-but-cannot-be-asked-for)
- [An answer that differs from the reference](#an-answer-that-differs-from-the-reference)
- [Write a client that survives](#write-a-client-that-survives)
- [Checklist](#checklist)

## Between releases

Only 5.5-20260924 was available for this guide. What is known about other releases comes from notes of earlier work, and is marked.

| What | Reported, not tried on this release |
| ---- | ----------------------------------- |
| Names change between releases. Check the reference of **your** version (`https://<server>:<admin port>/api/v2.0/docs/index.html`) before you rely on a field. | Reported |
| The setting `Webservices.Admin.CsrfToken.enabled` is on by default from the 20230525 release. A script written before it, that keeps a session and sends no `csrfToken`, can fail on a current server that enforces it. | Reported. On 5.5-20260924 the option is on, and the lab still accepted a write without the token: see [Authentication and sessions](authentication-and-sessions.md). |
| The current administrator's login name is the field `loginName` on `GET /myself` (seen on 5.5-20260827 and on 5.5-20260924), and not `name`. | Tried here on 5.5-20260924, reported for 5.5-20260827 |

The only safe rule is to treat every name you did not try on your own server as a guess.

## The same thing, two names

Tried on the lab (an end user with a file transfer, and the Admin API):

| The thing | End User list `GET /transfers` | End User single `GET /transfers/{id}` | Admin `GET /logs/transfers` |
| --------- | ------------------------------ | ------------------------------------- | --------------------------- |
| File name | `filename` | `file` | `filename` |
| Size | `filesize` | `size` | `filesize` |
| Folder on the remote side | `remoteDir` | `remoteFolder` | `remoteDir` |
| Direction | `direction`: `Incoming`, `Outgoing` | `transferType`: `User upload`, `User download` | `incoming`: `true`, `false` |
| The id of the transfer | `transferId`, a string that holds characters you must encode in a URL | `transferId` | `id`, an **object** with `mTransferStatusId`, `mTransferStartTime` and `urlrepresentation` |
| Start time | `startTime` (RFC 2822 with an offset) | `startTime` | `startTime` |

The list and the single object of the End User API have 19 and 38 names. They share only 10 of them (`account`, `coreId`, `duration`, `login`, `operationIndex`,
`protocol`, `securityParameters`, `startTime`, `status` and `transferId`). A script that reads a transfer from the list and then asks for the single object cannot reuse its names.

The name of the user also differs by place:

| Where | The user's name is in |
| ----- | --------------------- |
| Admin `GET /myself` | `loginName` (there is no `name`) |
| Admin `GET /administrators/{name}` | `loginName` |
| Admin `GET /accounts` items | `name` |
| End User `GET /myself` | `name` |

The dates have their own differences between resources: see
[Time formats in the SecureTransport REST API, and daylight saving time](time-formats.md).

## Two shapes for a list

The Admin API wraps a list: `{"resultSet": {"returnCount": ..., "totalCount": ...}, "result": [ ... ]}`. The End User API answers a **plain array** for `/transfers`, `/myself/addressBook` and
`/secretQuestions`. A client that does `answer["result"]` on an End User list fails, and a client that does `len(answer)` on an Admin list counts the two keys.

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts?limit=1&fields=name" -H "accept: application/json" -H "Referer: x"
```

```text
{
  "resultSet" : { "returnCount" : 1, "totalCount" : 17 },
  "result" : [ { "type" : "user", "name" : "anonymous" } ]
}
```

`totalCount` is the number of objects that match. `returnCount` is the number in this answer, and it is capped by `limit`. Read `totalCount` to count.

## Names that are returned but cannot be asked for

On the Admin API, `fields=` limits what a list returns. For two names it does not work, although the answer has them:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers?fields=serverName&limit=1" -H "accept: application/json" -H "Referer: x"
```

```text
{ ... "result" : [ { "protocol" : "as2", "serverName" : "As2 Default" } ] }
```

The answer has `protocol`, which you did not ask for. And when you do ask for it:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers?fields=protocol&limit=1" -H "accept: application/json" -H "Referer: x"
```

```text
{ "message" : "Error validating request", "validationErrors" : [ "Field protocol does not exist." ], ... }
```

The same is true of `type` on `/sites` (`fields=type` answers 400 "Field type does not exist."). The field that tells the kind of an object is always there, and you cannot name it.
Do not put it in `fields=`. Read it from the answer.

The End User API has no `fields=`: a call with `fields=filename` on `/transfers` was **not refused**, and returned every field. Do not rely on `fields=` to make an End User answer small.

## An answer that differs from the reference

On this release, the answer to a **daemon operation** is a bare list. The reference describes an object that holds the list.

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/operations?operation=start&daemon=ftp" -H "accept: application/json" -H "Referer: x"
```

```text
[ {
  "daemon" : "FTP",
  "message" : "Daemon FTP is already started.",
  "isSuccessful" : false
} ]
```

(That call was made on a daemon that was running, so it changed nothing. A real start answers the same shape with `"Daemon FTP is started."` and `true`.) The reference says
`{"daemonOperationResults": [ ... ]}`. A server operation (`POST /servers/operations`) answers an object, `{"serverStatuses": [ ... ]}`, as the reference says. The Admin examples of this
repository read it, and their online check passed on this lab.

Write the reader for both. In both cases, read `isSuccessful` and not the status code: a 200 can mean that it did not work.

```bash
jq -r '(if type == "array" then . else (.daemonOperationResults // [.]) end)[] | "\(.daemon) \(.message) (successful: \(.isSuccessful))"'
```

## Write a client that survives

### 1. Look the field up first

Take the first name that exists. When none does, say which names the object has: a missing field is then a clear error, not an empty value.

```python
def first_field(obj, *names):
    """The value of the first of `names` that obj has. Raises with the names obj does have."""
    for name in names:
        if name in obj:
            return obj[name]
    raise KeyError("none of %s is in the answer. It has: %s" % (", ".join(names), ", ".join(sorted(obj))))

me = first_field(answer, "loginName", "name")                    # an administrator, on any release that uses either
size = first_field(transfer, "filesize", "size")                 # a list item, or a single transfer
```

The repository's `stCertificateExpiry.py` does the same for the certificate fields, and prints the names it found when none matches.

### 2. Read the version first

`GET /version` gives the release. The examples in `Features` stop when the server is older than the release that brought the feature.
`Features/lib/st_feature_check.sh` does the check. A version looks like `5.5-20260924`, and the date part is compared too.

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/version" -H "accept: application/json" -H "Referer: x"
```

```text
{ "serverType" : "ST-Core-Server", "version" : "5.5-20260924", "build" : "1813", "os" : "Linux", ... }
```

`GET /version` is an Admin API call. The End User API has none: the same path on the End User port answered 404. A client that only has an end user account cannot ask for the
release. It has to be given the release in its settings, or it has to read the names as described above.

To compare two versions in a program, turn each into a key that sorts:

```python
import re

def version_key(text):
    """'5.5-20260924' -> (5, 5, 20260924). A version with no date part is the base release, so it sorts before every dated update of it."""
    m = re.match(r"^(\d+)\.(\d+)(?:\.\d+)?(?:-(\d{6})(\d{2})?)?", text)
    if not m:
        raise ValueError("not a version: %r" % text)
    date = int((m.group(3) or "0") + (m.group(4) or "00"))
    return (int(m.group(1)), int(m.group(2)), date)

version_key("5.5-20260924") > version_key("5.5")      # True
```

### 3. Ask for fields, and fall back

When you need few fields from the Admin API, ask for them with `fields=`. If a field is refused with 400 "Field ... does not exist", ask again without `fields=` and pick what you
need. Do not put `protocol` or `type` in `fields=`, and do not use `fields=` with the End User API.

### 4. Keep the reference of your own release

The Open API page of the server you talk to is the reference for that server: `https://<server>:<admin port>/api/v2.0/docs/index.html`. The End User API has its own, on the End
User port. Look the field up there, and then try it on your server. Where the two differ, as in the daemon answer above, the server is what your script meets.

## Checklist

- [ ] No field name is used that was not read in an answer from your own server.
- [ ] A client for a transfer reads `filename` or `file`, `filesize` or `size`, `remoteDir` or `remoteFolder`, in the list and in the single object.
- [ ] A reader of a list handles the Admin envelope and the End User plain array.
- [ ] `fields=` never names `protocol` or `type`, and is not used with the End User API.
- [ ] An answer to an operation is read as a bare list or an object, and `isSuccessful` is read.
- [ ] The client reads `GET /version` on the Admin API, or is told the release.
- [ ] A missing field makes the client say which names the answer has.
