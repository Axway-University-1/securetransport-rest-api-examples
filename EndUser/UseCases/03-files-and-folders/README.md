# 03 Files and folders

**Use case:** manage files the way a person does, from start to finish: create a folder, put a file in it, list it, read it, look at its details, update it, rename it, and delete it and the folder.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`EndUser/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

One story in eleven steps, on one folder of the home folder (`example_uc_files`) and one file in it. The folder is made by 01 and
removed by 11; 99 removes both by their exact names if a run stopped halfway.

## The examples

Run them in order: each one builds on the one before it (`00.run_all.sh` runs
them all, and ends with `99.cleanup_DELETE.sh`). Every script checks for an active session
first and logs in when there is none, so each can also be run on its own once what it needs is there.

| Script | What it does | Copied from (`EndUser/API 2.0/bash`) |
| ------ | ------------ | ------------------------------------ |
| `01.folder_POST` | Create the folder. If it is there already, say so and do nothing. | `02.Files/02.files_name_POST_folder.sh` |
| `02.files_POST_upload` | Upload a file into it: the folder in the URL, the name in the form. | `02.Files/04.files_filepath_POST.sh` |
| `03.files_GET_list` | List it, then sorted, limited, glob-filtered, and the folder's own metadata. | `02.Files/09.files_GET_query.sh` |
| `04.files_GET_read` | Read the content, and keep a copy in `downloaded_files/`. | `02.Files/03.files_filepath_GET.sh` |
| `05.files_GET_metadata` | Read about the file without reading it: size, rights, time, MD5. | `02.Files/10.files_filepath_GET_metadata.sh` |
| `06.files_POST_overwrite` | Update it: upload under the same name, then read it back. | `02.Files/04.files_filepath_POST.sh` |
| `07.files_PATCH_rename` | Rename it with a JSON patch (`/newFilePath`). A 403 right after an upload is tried again. | `02.Files/13.files_filepath_PATCH_rename.sh` |
| `08.files_PATCH_rename_missing` | Rename the name 07 renamed away: refused with 403, not 404, and a read of it says it is not there. | `02.Files/13.files_filepath_PATCH_rename.sh` |
| `09.files_POST_folder_in_name` | Put the folder in the filename instead of the URL: 201, and the file lands in the home folder. Shown, then removed. | `02.Files/04.files_filepath_POST.sh` |
| `10.files_DELETE_file` | Delete it, then show that a read of it is 404. | `02.Files/07.files_filepath_DELETE.sh` |
| `11.folder_DELETE` | Delete the folder: refused (403) while it has a file, then done once it is empty. | `02.Files/07.files_filepath_DELETE.sh` |
| `99.cleanup_DELETE` | Removes the file (under both names), anything 09 left in the home folder, and the folder, by exact name, and ends the session. |  |

`lib.sh` is the one small file they share: it loads `../session.sh` (the settings, the
session helper `st_session`, and the cookie jar of this use case, `session.cookie.jar`, which git
ignores), and the names it works with.

## What to take from it

- The folder goes in the URL of an upload (`POST /files/<folder>`) and the name in the form. A filename with a folder in it (`-F "file=@x;filename=docs/x.txt"`) is cut down to its last part, and the file lands in the home folder, with a 201 and no warning: 09 shows it.
- Creating a folder needs a body that says it is a directory; creating one that exists is refused with 409, so 01 looks first.
- There is no update call for a file's content: uploading under the same name replaces it (201, 06).
- **A 403 on a rename or a delete does not always mean "no access".** A rename of a name that is not there answers 403, not 404 (08). A delete of a folder that still has files answers 403 "Unable to delete directory: /docs. (directory is not empty)" (11): delete bottom up, by exact name. When a script gets a 403, it reads the file's metadata (`?metadata=true`, 200 or 404) before it believes the reason.
- A rename a moment after the upload of the same file can answer 403 too, for a few seconds. 07 tries again, up to 10 times; 08 does not, because there the file really is not there.
- The occasional 500 on an upload that was right, and the upload that is refused but stored all the same, are the subject of [04-larger-files](../04-larger-files/README.md): after any answer that is not 201, do not trust the file that is there.
- `curl -G` with `--data-urlencode` builds a query and encodes the values; a glob goes in the path.
- **The home folder outlives the account.** Deleting the account does not delete its files: a new account with the same home folder sees them. The cleanup of this use case therefore deletes by exact name, and does not count on the account's removal to clean up (the online check proves it: it uploads a file, deletes the account, makes it again and reads the file).
- Sharing a folder (`PATCH` of `sharedDirectoryProperties`, `02.Files/14` and `15`) has its own use case, [06-sharing-a-folder](../06-sharing-a-folder/README.md): it needs an account with an e-mail address, which `john` on the lab does not have (400, "Shared folders functionality is disabled").

## Tests

`tests/offline/checks/test_bash_enduser_usecases.sh` runs every script against a stub `curl`.
`tests/online/checks/63.enduser_usecases_scripts.py` runs them on a real server, as a
throwaway end user account it creates and removes, and checks that nothing is left behind.
