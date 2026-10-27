# Moving files with the End User API

**For:** integrators and administrators who upload, download, rename, delete and share files with scripts through the End User API.
**Checked on:** SecureTransport 5.5-20260924. Everything marked "tried" was run on the lab with throwaway accounts. A statement marked "not tried" comes from the
reference or from earlier notes.

## Summary

Uploading a file is one call. The hard part is knowing what happened when something goes wrong. Several answers on this version do not say what you would expect: a missing
file on a rename is a 403, a refused upload can leave a file behind, and a refused chunk can leave a file of the full size. This guide shows each call, what it answers,
and a way to be sure that a file arrived whole. At the end it shows sharing a folder.

- [Before you start](#before-you-start)
- [Upload with a multipart form](#upload-with-a-multipart-form)
- [Check the file: the checksum](#check-the-file-the-checksum)
- [Text and binary](#text-and-binary)
- [Upload in chunks](#upload-in-chunks)
- [Upload to a file operation with a form](#upload-to-a-file-operation-with-a-form)
- [Download, rename and delete](#download-rename-and-delete)
- [When an upload answers 500](#when-an-upload-answers-500)
- [Share a folder](#share-a-folder)
- [Checklist](#checklist)

## Before you start

- The End User API has its own port. It is often the Admin port minus one, but not always: look at your server. The examples use `${ST_ENDUSER_PORT:-8443}`.
- The user and password are those of an end user account, not an administrator. The examples use `${ST_USER}` and `${ST_PASSWORD}` for them.
- Every call sends the `Referer` header, and the examples use Basic authentication (see [Authentication and sessions](authentication-and-sessions.md)).
- Paths are relative to the home folder of the user: `/docs/report.txt` is `docs/report.txt` in the home folder.
- An account's home folder outlives the account. When an account is deleted, its files stay on disk, and an account made later with the same home folder can see them
  (reported in earlier notes, not tried again). A new account does not always start with an empty folder.

Make a folder first. The body only says that it is a folder:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/files/docs" \
  -H "Content-Type: application/json" -H "accept: application/json" -H "Referer: x" -d '{"isDirectory": true}'
```

The answer is 201. The same call for a folder that exists is 409 (tried earlier, not repeated).

## Upload with a multipart form

The folder goes in the **URL**. The form has the file, and the name it gets:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/files/docs" \
  -F "file=@report.txt;filename=report.txt" -H "accept: application/json" -H "Referer: x"
```

The answer is 201. Things that were tried:

- **The same name again.** The call answers 201 again, and the file is **replaced**. There is no "file exists" answer.
- **A folder in the file name.** `filename=docs/nested.txt` posted to `/files` was answered 201, but the file is **not** in `docs`. The server keeps only the last part
  of the name and stores the file in the home folder as `nested.txt`. To put a file in a folder, put the folder in the URL: `POST /files/docs`.

## Check the file: the checksum

There are two ways to ask the server to check the file.

**1. Send the checksum with the upload.** The `Content-MD5` header is the MD5 of the file as **base64 of the binary value** (not the hex text):

```bash
MD5=$(openssl dgst -md5 -binary report.txt | openssl base64)
```

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/files/docs" \
  -H "Content-MD5: ${MD5}" -F "file=@report.txt;filename=report.txt" -H "accept: application/json" -H "Referer: x"
```

A right checksum answers 201. A wrong one answers **500**, with `Error while uploading file to location: /docs` (see
[When an upload answers 500](#when-an-upload-answers-500)).

**2. Ask the server for the checksum afterwards.** Start an `MD5Calc` operation, and read it until it is `DONE`:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/fileOperations" \
  -H "Content-Type: application/json" -H "accept: application/json" -H "Referer: x" -d '{"operation": "MD5Calc", "filePath": "/docs/report.txt"}'
```

```text
{ "id" : "7ba249b7-6dca-49db-b4f2-4e1355db7b37", "status" : "IN_PROGRESS" }
```

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/fileOperations/7ba249b7-6dca-49db-b4f2-4e1355db7b37" \
  -H "accept: application/json" -H "Referer: x"
```

```text
{ "id" : "7ba249b7-...", "status" : "DONE", "result" : { "md5Checksum" : "WdDRn8RcppIw2Fj2ClVX+A==", "fileSize" : 7 } }
```

The `md5Checksum` is base64, as in the header, so compare it with the same `openssl` line. In the test it matched the local value.

## Text and binary

The query parameter `transferMode` is `BINARY` or `ASCII`. Without it the file is stored as it is sent.

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/files/docs?transferMode=ASCII" \
  -F "file=@notes.txt;filename=notes.txt" -H "accept: application/json" -H "Referer: x"
```

Tried with a file of `a`, `b` and Windows line ends (`CR LF`):

| transferMode | Bytes stored |
| ------------ | ------------ |
| `BINARY` | `61 0d 0a 62 0d 0a` (unchanged) |
| `ASCII` | `61 0a 62 0a` (the `CR` is removed) |

Use `BINARY` for anything that is not text, and for text that must stay byte for byte the same.

## Upload in chunks

A big file can go up in pieces. This is a **file operation**:

1. `POST /fileOperations` with `{"operation": "Upload", "filePath": "/docs/big.bin", "customAttributes": {"transferMode": "BINARY"}}`. The answer has an `id`.
2. `PUT /fileOperations/{id}` for each piece, with `Content-Type: application/octet-stream` and `Content-Range: bytes <first>-<last>/<size>`, **in order**.
3. Check the file (the checksum, above).

```bash
# Upload big.bin in pieces of 1,000,000 bytes
BASE="https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0"
SIZE=$(wc -c < big.bin | tr -d ' ')       # macOS pads the number with spaces
CHUNK=1000000
ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${BASE}/fileOperations" -H "Content-Type: application/json" \
  -H "accept: application/json" -H "Referer: x" \
  -d '{"operation": "Upload", "filePath": "/docs/big.bin", "customAttributes": {"transferMode": "BINARY"}}' | jq -r '.id')
START=0
while [ "${START}" -lt "${SIZE}" ]; do
  END=$(( START + CHUNK - 1 )); [ "${END}" -ge "${SIZE}" ] && END=$(( SIZE - 1 ))
  tail -c +$(( START + 1 )) big.bin | head -c $(( END - START + 1 )) | curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${BASE}/fileOperations/${ID}" \
    -H "Content-Type: application/octet-stream" -H "Content-Range: bytes ${START}-${END}/${SIZE}" -H "Referer: x" --data-binary @- -o /dev/null -w "%{http_code}\n"
  START=$(( END + 1 ))
done
```

Tried with three pieces of a 1,240 byte file:

- Each piece in order answered **200**. The file had the right size and the same bytes as the original.
- The operation still said `IN_PROGRESS` after the last piece, although the file was whole. The status is the status of the operation, not of the file. Check the file, not the status.
- A piece sent **out of order** (the last piece first) answered **500**. See the next section for what was left behind.

## Upload to a file operation with a form

An upload operation also takes a multipart form: `POST /fileOperations/{id}` with `-F "file=@..."`. The file is stored under the **name of the local file**, not the
`filePath` of the operation, unless the form gives `filename=` (tried):

| Form | Name on the server |
| ---- | ------------------ |
| `-F "file=@local_name.bin"` | `local_name.bin` |
| `-F "file=@local_name.bin;filename=wanted2.bin"` | `wanted2.bin` |

Always give `filename=`.

## Download, rename and delete

Download with `GET /files/{path}`:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/files/docs/report.txt" -H "Referer: x" -o report.txt
```

A file that is not there answers 404.

Rename with a `PATCH` that adds `/newFilePath`:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/files/docs/report.txt" \
  -H "Content-Type: application/json" -H "Referer: x" -d '[{"op": "add", "path": "/newFilePath", "value": "/docs/renamed.txt"}]'
```

The answer is 204. The same rename for a file that is **not there** answers **403**, not 404. A script that treats 403 as "no access" is misled: look at the file first
(`GET /files/{path}?metadata=true` answers 200 or 404).

Delete with `DELETE /files/{path}`:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/files/docs/renamed.txt" -H "Referer: x"
```

A file answers 204. A folder that still has files answers **403**, with "Unable to delete directory: /docs. (directory is not empty)". Delete the files first, then the folder.

## When an upload answers 500

A 500 on an upload does **not** mean that nothing was stored. Tried:

- **A wrong `Content-MD5`:** the answer was 500, and the file **was stored**, with the full size and the same bytes as the one sent. The server recorded the right MD5 of what it
  received in the file's metadata.
- **A chunk out of order:** the answer was 500, and a file of the **full declared size** (300 bytes of a 300 byte upload) was listed, although only the last 100 bytes were sent.
- **A valid upload, now and then:** a 500 was also seen for uploads that were right. About 3 in 100 in earlier runs on this lab, and none in 100 uploads on the day of this check.
  It cannot be made to happen on demand.

So, after any answer that is not 201 (or 200 for a chunk):

1. Do not trust the file that is there.
2. Ask for the checksum (`MD5Calc`) and compare it with yours.
3. If it differs, or you are not sure, **upload again**. An upload over an existing name replaces the file (201).
4. Compare again.

An upload that answers 201 and has the right checksum is whole. Keep the check in the script: a retry without the check can leave a bad file in place.

## Share a folder

A folder can be shared with another user of the server. The call is a `PATCH` of the folder that adds `sharedDirectoryProperties`:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "https://${ST_SERVER}:${ST_ENDUSER_PORT:-8443}/api/v2.0/files/docs" \
  -H "Content-Type: application/json" -H "Referer: x" \
  -d '[{"op": "add", "path": "/sharedDirectoryProperties", "value": {"isOwner": true, "collaborators": ["other.user@example.com"], "shareRights": 1, "enableNotifications": false, "enableOwnerNotifications": false, "showCollaboratorsToAll": false}}]'
```

The answer is 204. What was tried:

- **The owner must have an e-mail address.** For an account without one, the same call was answered 400, "Unable to complete the operation. Shared folders functionality is disabled." The
  server's sharing feature was on: the message points at the wrong thing. `GET /myself` shows `sharingAllowed: false` for such an account. An open session does not see an address
  added later (see [Authentication and sessions](authentication-and-sessions.md)).
- **`shareRights`:** 1, 3 or 7.

  | shareRights | The collaborator can |
  | ----------- | -------------------- |
  | 1 | read. An upload was refused with 403. |
  | 3 | read and upload (201). Deleting their own upload was refused with 403. |
  | 7 | read, upload and delete. Deleting their own upload answered 204. |

- **Change the rights** with a `replace` of `/sharedDirectoryProperties/shareRights`.
- **What the collaborator sees:** in their root folder, the folder is named `<folder> (<owner e-mail>)`, for example `docs (owner@example.com)`.
- **The first read can be late.** After the 204, the collaborator's list already shows the folder, but a read of a file in it was answered 403 for a moment in some runs, and
  200 in others. Read again after two seconds, a few times, before you call it a failure.
- **Stop sharing** with a `remove` of `/sharedDirectoryProperties` (204). The folder is gone from the collaborator's root, and stays with the owner.

The shipped use case `EndUser/UseCases/06-sharing-a-folder` runs these steps.

## The shipped examples

| What | Where |
| ---- | ----- |
| One call at a time | `EndUser/API 2.0/bash/02.Files`, `04.FileOperations` |
| Files and folders, start to finish | `EndUser/UseCases/03-files-and-folders` |
| Larger files, checksums, chunks, forms | `EndUser/UseCases/04-larger-files` |
| Sharing a folder | `EndUser/UseCases/06-sharing-a-folder` |

## Checklist

- [ ] The folder is in the URL. A name with a folder in it is not a folder.
- [ ] Each upload has a `Content-MD5`, or is checked with `MD5Calc` afterwards.
- [ ] `transferMode` is `BINARY` unless the file is text and its line ends may change.
- [ ] A form upload to an operation gives `filename=`.
- [ ] After a 500 the script checks the file and uploads again, and does not trust a file that is there.
- [ ] A 403 on a rename or a delete is read as "not there" or "not empty" as well as "no access".
- [ ] A read after a share is retried for a few seconds.
