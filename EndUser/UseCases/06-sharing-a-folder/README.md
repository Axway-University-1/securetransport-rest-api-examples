# 06 Sharing a folder

**Use case:** let another user work in one of your folders: share it, see how it is shared, change what the other user may do, stop sharing, and clean up.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`EndUser/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

## Before you run it

Two things have to be true, and neither is in your control as an end user:

1. **Your account has an e-mail address.** `GET /myself` says `sharingAllowed: true` only then. Without one, a share is refused
   with `400 "Shared folders functionality is disabled"`, which sounds like a server setting and is not. Step 01 checks it and stops
   with the reason (exit 3).
2. **You name a user the server knows**, by e-mail address: `export ST_SHARE_WITH=their.address@example.com`. An address the server
   does not know is refused. `02-knowing-yourself/05.myself_addressBook_GET.sh` lists the users and their addresses. Nobody is sent an
   e-mail by these examples (notifications are off), but pick a user who expects a shared folder on a lab.

## The examples

Run them in order (`00.run_all.sh` runs them all, and ends with `99.cleanup_DELETE.sh`).

| Script | What it does | Copied from (`EndUser/API 2.0/bash`) |
| ------ | ------------ | ------------------------------------ |
| `01.sharing_GET_myself` | May this account share? `sharingAllowed` and the e-mail address. Exit 3 when not. | `03.Myself/01.myself_GET.sh` |
| `02.folder_POST` | Create the folder `example_uc_shared`, with a file in it. | `02.Files/02.files_name_POST_folder.sh` |
| `03.folder_PATCH_share` | Share it with `ST_SHARE_WITH`, read only (`shareRights` 1). | `02.Files/14.files_filepath_PATCH_share.sh` |
| `04.folder_GET_sharing` | How it is shared: owner, who with, the rights in words. | `02.Files/10.files_filepath_GET_metadata.sh` |
| `05.folder_PATCH_rights` | Change the rights without sharing again: 3, then 7, each read back. | `02.Files/14.files_filepath_PATCH_share.sh` |
| `06.folder_PATCH_unshare` | Stop sharing, and check the folder is no longer shared. | `02.Files/15.files_filepath_PATCH_unshare.sh` |
| `07.folder_DELETE` | Delete the file, then the folder. | `02.Files/07.files_filepath_DELETE.sh` |
| `99.cleanup_DELETE` | Unshares, deletes the file and the folder by their exact names, ends the session. | |

`lib.sh` is the one small file they share: it loads `../session.sh` and names the folder, the file and the user to share with.

## What to take from it

- **The rights** (`shareRights`): **1** read, **3** read and upload, **7** read, upload and delete. Confirmed with a second user: with 1 an
  upload and a delete are refused (403); with 3 an upload works (201) and deleting their own file is still 403; with 7 both work, and they can delete
  your files too. Start with 1.
- **What the other user sees:** the folder in the root of their own home folder, named `example_uc_shared (your.address@example.com)`: your name for it
  and your address in brackets. It is an ordinary folder in their list (so the path has spaces and brackets: URL-encode it).
- **Changing the rights is a `replace` of one field** (`/sharedDirectoryProperties/shareRights`), not a new share. A share is an `add` of the whole
  `/sharedDirectoryProperties`, and stopping is a `remove` of it: the folder and its files stay with you.
- A shared folder shows `isShared: true` and a `sharedDirectoryProperties` object (owner, collaborators, rights) in its metadata.
- The message of a refused share does not say why: "functionality is disabled" is an account with no e-mail address; "Unable to share folder ... with
  user ..." is an address the server does not know. (Both are in the product team's list of known issues.)
- The folder must be your own. Deleting a shared folder takes it away from the other user too, so the cleanup stops sharing first.

## Tests

`tests/offline/checks/test_bash_enduser_usecases.sh` runs every script against a stub `curl`.
`tests/online/checks/66.enduser_usecase_sharing.py` runs them on a real server with three throwaway accounts (an owner and a collaborator with an
e-mail address, and one without), and reads what the collaborator really sees and may do at each rights value through the API.
