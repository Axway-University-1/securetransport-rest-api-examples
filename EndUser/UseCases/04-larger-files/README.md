# 04 Larger files

**Use case:** send files that matter: have the server check them on the way in, know what to do when an upload is refused, ask it for a checksum afterwards, choose text or binary, send one in pieces (and see what goes wrong out of order), send one by the two-step way, and send several in a loop.

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
| `02.files_POST_md5` | Upload with a `Content-MD5` header: a right checksum is 201, a wrong one is refused (500). | `02.Files/11.files_filepath_POST_md5.sh` |
| `03.files_POST_md5_refused` | When an upload is refused: look at what the server holds anyway, compare its MD5 with the local one, delete it, send it again with the right checksum, and end verified. | `02.Files/11`, `02.Files/10`, `02.Files/07`, `04.FileOperations/01` |
| `04.fileOperations_POST_md5calc` | Ask the server for the MD5 of what it holds (an operation, followed until DONE) and compare with the local one. | `04.FileOperations/01.fileOperations_POST_md5calc.sh` |
| `05.files_POST_text_binary` | The same two lines with CR LF line ends, uploaded as ASCII and as BINARY, read back, in hex: ASCII drops the CR. | `02.Files/04`, `02.Files/03` |
| `06.fileOperations_PUT_chunked` | Upload in pieces, each with a `Content-Range`, in order; then check the MD5 of the file, because the operation stays IN_PROGRESS. | `04.FileOperations/03.fileOperations_id_PUT_chunked.sh` |
| `07.fileOperations_PUT_out_of_order` | Send the last piece first: refused (500), and a file is listed all the same, but its MD5 is not the local one. | `04.FileOperations/02`, `03`, `01` |
| `08.fileOperations_POST_multipart` | The two-step upload with the content as one multipart form; then the same with no `filename=`, which stores the local file's name. | `04.FileOperations/04.fileOperations_id_POST_multipart.sh` |
| `09.files_POST_bulk` | Several uploads in a loop, stopping at the first refusal. | `02.Files/05.files_filepath_POST_v2.sh` |
| `99.cleanup_DELETE` | Removes the files and the folder, by exact name, and ends the session. |  |

`lib.sh` is the one small file they share: it loads `../session.sh` (the settings, the
session helper `st_session`, and the cookie jar of this use case, `session.cookie.jar`, which git
ignores), the names it works with, and the helpers: a sample file and its MD5, the MD5 the server computes (`st_md5calc`), and an upload with or without a `Content-MD5`.

## What to take from it

- The checksum is base64 of the 16 raw bytes, not the hex text `md5sum` prints (`openssl dgst -md5 -binary | openssl base64`). The server answers an `MD5Calc` operation in the same form (`md5Checksum`), so the two compare with a plain `=`.
- **A 500 on an upload does not mean that nothing was stored.** A wrong `Content-MD5` is refused with 500 and the file is stored all the same, in full (03). A piece out of order is 500 and a file is listed, with a size that can look right, and is not whole (07). A valid upload can also get a 500 now and then; it cannot be made to happen on demand. After any answer that is not 201 (or 200 for a piece): do not trust the file that is there, ask for its MD5 and compare, and if it differs or you are not sure, upload again over it (an upload over an existing name replaces the file, 201), and compare again. Keep the check in the script: a retry without it can leave a bad file in place.
- Starting an operation answers at once; the work is done later, so follow `GET /fileOperations/<id>` until it is DONE. An upload operation is different: it says IN_PROGRESS after the last piece although the file is whole. The status is the status of the operation, not of the file: check the file.
- `Content-Range: bytes START-END/TOTAL` counts from 0 and includes both ends, and the pieces go **in order**. 06 cuts the pieces with `tail -c +` and `head -c`, and takes the size with `wc -c < file | tr -d ' '` (macOS pads the number with spaces).
- `transferMode` is `BINARY` or `ASCII`. Without it the file is stored as it is sent. ASCII turns the line ends CR LF into LF (05): use `BINARY` for anything that is not text, and for text that must stay byte for byte the same.
- A multipart upload to an operation stores the file under the name of the local file unless the form gives `filename=` (08). Always give `filename=`.
- An upload over an existing name replaces it with a 201 (see also 03-files-and-folders/06). A folder in the filename is cut off, as in [03-files-and-folders](../03-files-and-folders/README.md) (09).

## Tests

`tests/offline/checks/test_bash_enduser_usecases.sh` runs every script against a stub `curl`.
`tests/online/checks/63.enduser_usecases_scripts.py` runs them on a real server, as a
throwaway end user account it creates and removes, and checks that nothing is left behind.
