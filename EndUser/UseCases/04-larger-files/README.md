# 04 Larger files

**Use case:** send files that matter: have the server check them on the way in, ask it for a checksum afterwards, send one in pieces, send one by the two-step way, and send several in a loop.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`EndUser/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

A plain upload is one request, and nothing says the file arrived whole. These examples add what makes a transfer trustworthy:
an MD5 on the way in, an MD5 asked for afterwards, and uploads that can be sent in pieces. The samples are made here,
of a known size and content, so what the server should say about them is known.

## The examples

Run them in order: each one builds on the one before it (`00.run_all.sh` runs
them all, and ends with `99.cleanup_DELETE.sh`). Every script checks for an active session
first and logs in when there is none, so each can also be run on its own once what it needs is there.

| Script | What it does | Copied from (`EndUser/API 2.0/bash`) |
| ------ | ------------ | ------------------------------------ |
| `01.folder_POST` | Create the folder `example_uc_large`. | `02.Files/02.files_name_POST_folder.sh` |
| `02.files_POST_md5` | Upload with a `Content-MD5` header: a right checksum is 201, a wrong one is refused. | `02.Files/11.files_filepath_POST_md5.sh` |
| `03.fileOperations_POST_md5calc` | Ask the server for the MD5 of what it holds (an operation, followed until DONE) and compare with the local one. | `04.FileOperations/01.fileOperations_POST_md5calc.sh` |
| `04.fileOperations_PUT_chunked` | Upload in pieces, each with a `Content-Range`. | `04.FileOperations/03.fileOperations_id_PUT_chunked.sh` |
| `05.fileOperations_POST_multipart` | The two-step upload with the content as one multipart form. | `04.FileOperations/04.fileOperations_id_POST_multipart.sh` |
| `06.files_POST_bulk` | Several uploads in a loop, stopping at the first refusal. | `02.Files/05.files_filepath_POST_v2.sh` |
| `99.cleanup_DELETE` | Removes the files and the folder, by exact name, and ends the session. |  |

`lib.sh` is the one small file they share: it loads `../session.sh` (the settings, the
session helper `st_session`, and the cookie jar of this use case, `session.cookie.jar`, which git
ignores), the names it works with, and two helpers for a sample file and its MD5.

## What to take from it

- The checksum is base64 of the 16 raw bytes, not the hex text `md5sum` prints (`openssl dgst -md5 -binary | openssl base64`).
- A wrong `Content-MD5` is refused (500 on the lab), and nothing is stored under that name.
- Starting an operation answers at once; the work is done later, so follow `GET /fileOperations/<id>` until it is DONE.
- `Content-Range: bytes START-END/TOTAL` counts from 0 and includes both ends.
- A multipart upload to an operation stores the file under the name of the local file unless the form gives `filename=`.

## Tests

`tests/offline/checks/test_bash_enduser_usecases.sh` runs every script against a stub `curl`.
`tests/online/checks/63.enduser_usecases_scripts.py` runs them on a real server, as a
throwaway end user account it creates and removes, and checks that nothing is left behind.
