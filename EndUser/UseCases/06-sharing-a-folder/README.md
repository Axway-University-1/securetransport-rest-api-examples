# 06 Sharing a folder

**Use case:** let another user work in one of your folders: share it, choose what they may do, change it later, stop sharing, and clean up.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`EndUser/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

## Before you run it

Two things have to be true, and neither is in your control as an end user:

1. **Your account has an e-mail address.** `GET /myself` says `sharingAllowed: true` only then. Without one, a share is refused with
   `400 "Shared folders functionality is disabled"`, which sounds like a server setting and is not. Step 01 checks it and stops with the reason (exit 3).
   An administrator sets the address on the account (`PATCH /accounts/{name}`, `replace` `/contact/email`).
2. **You name a user the server knows**, by e-mail address, as the first parameter of 03: an address it does not know is refused.
   `02-knowing-yourself/05.myself_addressBook_GET.sh` lists the users and their addresses. Nobody is sent an e-mail by these examples
   (notifications are off), but pick a user who expects a shared folder on a lab.

### After an administrator sets the e-mail address: end the session and log in again

A session keeps what it learned at login. If you were logged in when the administrator set the address, **01 still says `sharingAllowed: false`
and 03 is still refused with the same 400, until you start a new session.** (Confirmed on the lab: the same session answered false, a new login true.)
End the session of this use case with `./99.cleanup_DELETE.sh` (it also removes the folder and the file this use case made, and stops any share of them),
then run the scripts again: the first one logs in anew. The messages of 01 and 03 say so when they refuse.

## The examples

Run them in order (`00.run_all.sh EMAIL [RIGHTS]` runs them all, and ends with `99.cleanup_DELETE.sh`; **without EMAIL it stops at once** with its usage, exit 2, before anything is created). The scripts take their input as parameters, like the other examples.

| Script | What it does | Copied from (`EndUser/API 2.0/bash`) |
| ------ | ------------ | ------------------------------------ |
| `01.sharing_GET_myself` | May this account share? `sharingAllowed` and the e-mail address. Exit 3 when not. | `03.Myself/01.myself_GET.sh` |
| `02.folder_POST` | Create the folder `example_uc_shared`, with a file in it. | `02.Files/02.files_name_POST_folder.sh` |
| `03.folder_PATCH_share EMAIL [RIGHTS]` | Share it with the user at EMAIL. RIGHTS is the type of share: `read` (the default), `write` or `full`. | `02.Files/14.files_filepath_PATCH_share.sh` |
| `04.folder_GET_sharing` | How it is shared: owner, who with, the rights in words. | `02.Files/10.files_filepath_GET_metadata.sh` |
| `05.folder_PATCH_rights RIGHTS` | Change the type of share without sharing again: `read`, `write` or `full`. | `02.Files/14.files_filepath_PATCH_share.sh` |
| `06.folder_PATCH_unshare` | Stop sharing, and check the folder is no longer shared. | `02.Files/15.files_filepath_PATCH_unshare.sh` |
| `07.folder_DELETE` | Delete the file, then the folder. | `02.Files/07.files_filepath_DELETE.sh` |
| `99.cleanup_DELETE` | Stops sharing, deletes the file and the folder by their exact names, ends the session. | |

```
./03.folder_PATCH_share.sh guest@example.com          # read only
./03.folder_PATCH_share.sh guest@example.com write    # they may also upload
./05.folder_PATCH_rights.sh full                      # they may also delete
./00.run_all.sh guest@example.com full                # the whole use case: shares as full, and tries write and full on the way
```

`lib.sh` is the one small file they share: it loads `../session.sh`, names the folder and the file, and turns `read`, `write` and `full` (or 1, 3 and 7) into the number the server takes.

## Choosing and changing the type of share

The type of share is the `shareRights` of the share. Name it as a word or as its number, in 03 when you share, and in 05 whenever you want it different:

| RIGHTS | Number | What the other user may do (confirmed with a second user on the lab) |
| ------ | ------ | -------------------------------------------------------------------- |
| `read` | 1 | List the folder and read its files. An upload and a delete are refused (403). |
| `write` | 3 | Also upload (201). Deleting a file, even their own, is still refused (403). |
| `full` | 7 | Also delete: their files and yours. |

- **Start with `read`** and widen it only when the other user needs more.
- **Changing it is a `replace` of one field** (`/sharedDirectoryProperties/shareRights`), not a new share: 05 does that, and takes effect at once. A share is an `add` of the
  whole `/sharedDirectoryProperties`, and stopping is a `remove` of it: the folder and its files stay with you.
- `04.folder_GET_sharing.sh` shows the type of share in words at any time.

## What to take from it

- **What the other user sees:** the folder in the root of their own home folder, named `example_uc_shared (your.address@example.com)`: your name for it
  and your address in brackets. It is an ordinary folder in their list (so its path has spaces and brackets: URL-encode it).
- A shared folder shows `isShared: true` and a `sharedDirectoryProperties` object (owner, collaborators, rights) in its metadata.
- The message of a refused share does not say why: "functionality is disabled" is an account with no e-mail address (or one the session has not yet seen); "Unable to share folder ... with
  user ..." is an address the server does not know. (Both are in the product team's list of known issues.)
- **Sharing a folder that does not exist is answered 204**, and nothing is shared: make the folder first (02), and read the metadata (04) to see that it is shared.
- The folder must be your own. Deleting a shared folder takes it away from the other user too, so the cleanup stops sharing first.

## Tests

`tests/offline/checks/test_bash_enduser_usecases.sh` runs every script against a stub `curl`.
`tests/online/checks/66.enduser_usecase_sharing.py` runs them on a real server with three throwaway accounts (an owner and a collaborator with an
e-mail address, and one without), proves that an open session does not see an e-mail address set later, and reads what the collaborator really sees and may do at each type of share through the API.
