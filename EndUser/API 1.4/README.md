# End User API 1.4 examples

> **For test environments only.** Read the [Disclaimer](../../README.md#disclaimer) before you run anything. The settings are those of an **end user**, not an
> administrator: copy `bash/set_variables.local.example.sh` to `bash/set_variables.local.sh` and fill in the user, his password and the End User port (8443, or 443 on a root install).

SecureTransport 5.5 still serves the older End User API 1.4 (`https://<server>:<port>/api/v1.4`) next to 2.0. **This folder is not a second copy of the
[End User 2.0 examples](../API%202.0/README.md).** It holds what 1.4 can do and 2.0 cannot. Most of that is the **mailbox**: sending a message to another user and reading it.

The examples are bash only (`curl` and `jq`), with no bat twins. Every call uses Basic authentication and a `Referer` header, with no session.

**Checked on:** SecureTransport 5.5-20260924. Where the text says "tried", it was run on a lab server of this version, with throwaway users. A call marked "not confirmed" was written from the reference and did
not give a result on that lab.

## What 1.4 has and 2.0 has not

The two references were compared (the 1.4 reference has 89 operations on 64 paths, the 2.0 one 28 on 17), and the candidates were tried on a lab.

| What | In 1.4 | In 2.0 |
| ---- | ------ | ------ |
| The **mailbox**: folders, drafts, send, reply, forward, attachments, search, history, anonymous links, registration (45 operations, 5 marked "Not implemented") | `/mailbox/...`, `/mailbox/messages/public` | nothing |
| The address book: create, change and delete an entry; the count and the settings of the user | `POST`, `PUT`, `DELETE /addressBook`, `/addressBook/count`, `/addressBook/myself` | only the read of `/myself/addressBook` |
| The password policy of the user | `GET /passwordPolicy` | nothing (404 on `/passwordPolicy` and on `/myself/passwordPolicy`) |

The mailbox is the large one, and it is what the examples here cover. The other two are in [Not covered](#not-covered).

## The mailbox examples

The mailbox is the mailbox of the user in `set_variables.local.sh`. A message goes from one user to another, so a full try needs two users: run the sender's examples with one settings file, and the recipient's with
another (`ST_ENDUSER_LOCAL_VARIABLES=/path/to/recipient.sh ./04.mailbox_folders_name_GET.sh`). The numbers are the order of a try: look, make a draft, send it, read it as the recipient, tidy up.

| Example | What it does | Result on the lab |
| ------- | ------------ | ----------------- |
| [`01.mailbox_myself_GET`](bash/01.Mailbox/01.mailbox_myself_GET.sh) | The mailbox user: name, email, licensed or not | works |
| [`02.mailbox_folders_GET`](bash/01.Mailbox/02.mailbox_folders_GET.sh) | The folders with their counts | works |
| [`03.mailbox_folders_POST NAME`](bash/01.Mailbox/03.mailbox_folders_POST.sh) | Makes a folder | works (204) |
| [`04.mailbox_folders_name_GET [FOLDER] [LIMIT]`](bash/01.Mailbox/04.mailbox_folders_name_GET.sh) | The messages of a folder, with their ids | works; needs `limit` and `offset` |
| [`05.mailbox_messages_POST_draft TO SUBJECT [MESSAGE] [SECURITY]`](bash/01.Mailbox/05.mailbox_messages_POST_draft.sh) | Makes a draft and prints its id | saved, but the call answers 500: the script finds the draft |
| [`06.mailbox_messages_id_GET MESSAGE_ID`](bash/01.Mailbox/06.mailbox_messages_id_GET.sh) | One message: sender, recipients, folder, unread, streams | works |
| [`07.mailbox_messages_id_send_PUT MESSAGE_ID [NOTIFY]`](bash/01.Mailbox/07.mailbox_messages_id_send_PUT.sh) | Sends a draft | works (200) |
| [`08.mailbox_messages_id_content_GET MESSAGE_ID STREAM_ID`](bash/01.Mailbox/08.mailbox_messages_id_content_GET.sh) | The text of a message | not confirmed: the text is empty |
| [`09.mailbox_messages_id_customProperties_GET MESSAGE_ID`](bash/01.Mailbox/09.mailbox_messages_id_customProperties_GET.sh) | The custom properties (`isRead`) | works |
| [`10.mailbox_messages_id_customProperties_PUT_read MESSAGE_ID [READ]`](bash/01.Mailbox/10.mailbox_messages_id_customProperties_PUT_read.sh) | Marks a message read or unread | works (204) |
| [`11.mailbox_messages_id_folder_PUT MESSAGE_ID FOLDER`](bash/01.Mailbox/11.mailbox_messages_id_folder_PUT.sh) | Moves a message to a folder | works (204) |
| [`12.mailbox_messages_id_DELETE MESSAGE_ID`](bash/01.Mailbox/12.mailbox_messages_id_DELETE.sh) | Deletes a message or a draft | works (200) |
| [`13.mailbox_folders_name_DELETE NAME`](bash/01.Mailbox/13.mailbox_folders_name_DELETE.sh) | Deletes an empty folder | works (200) |
| [`14.mailbox_search_GET [SUBJECT] [LIMIT]`](bash/01.Mailbox/14.mailbox_search_GET.sh) | Searches the mailbox | not confirmed: found nothing |
| [`15.mailbox_messageHistory_GET MESSAGE_ID`](bash/01.Mailbox/15.mailbox_messageHistory_GET.sh) | Who downloaded and who first opened a message | works |
| [`16.mailbox_attachments_POST MESSAGE_ID FILE`](bash/01.Mailbox/16.mailbox_attachments_POST.sh) | Adds a file to a draft | not confirmed: 422 |
| [`17.mailbox_attachments_GET MESSAGE_ID STREAM_ID FILENAME [OUTPUT]`](bash/01.Mailbox/17.mailbox_attachments_GET.sh) | Downloads an attachment | not confirmed: an empty file |

## What the mailbox did on the lab

All of this was tried on 5.5-20260924 with throwaway users.

- **A draft is saved and the call answers 500.** `POST /mailbox/messages` answers 500 "Draft was not saved." ("Internal error") with no id. The server log says "Draft created successfully", and also "Can not get package item input stream". The draft is in the Drafts
  folder. Example 05 reads the folder before and after, and takes the draft that is new.
- **A draft needs a security level.** Without `security` the draft is saved with the level null, and sending it is refused: 400 "Message security level may not be empty." The levels are `EXISTING_ACCOUNT`, `ENROLL_LICENSED`, `ENROLL_UNLICENSED`,
  `CHALLENGED_LINK` and `ANONYMOUS_LINK`; the examples use `EXISTING_ACCOUNT`.
- **A message to yourself stays in your Sent folder.** It is sent (200), and it does not arrive in your own Inbox. Use two users, and the recipient's address is the `email` of his mailbox user (01), which is the `contact.email` of his account.
- **Changing a draft is not reliable.** `PUT /mailbox/messages/{messageId}` answers 500 "Draft was not saved", and a draft that had been changed and given an attachment was refused at the send: 400 "Message recipient may not be empty." Make a new draft instead.
- **A folder lists nothing unless you give `limit` and `offset`.** `nRecords` says how many messages there are, and `data` is empty. Examples 04 and 14 always send both.
- **The text and the attachments are not stored.** A message that was sent arrives with a text of size 0 and, if one was added, an attachment of size 0 and a name. The upload answers 422 "Failed to process item upload", and the text answers 200 with an empty
  list. So 08, 14, 16 and 17 are not confirmed.
- **A sent message arrives with the same id.** The id of the draft is the id of the message in the Inbox of the recipient. A second send of the same draft also answers 200, and the recipient has it once.
- **Reading does not mark read.** `isRead` stays false until 10 sets it. After that the message is no longer `unread`, and the history of its first access holds the recipient.
- **The mailbox survives the account.** It is kept by the user's name. Delete an account and make it again with the same name, and its folders are there, and its folder listing shows the messages of the old account. Those cannot be opened or deleted any more:
  404 "The message you have requested is not available". **Delete the messages (12) and the folders (13) before you delete the account, and give a test user a name you do not use again.**
- **Refused or broken, with no example:** renaming a folder (`PUT /mailbox/folders/{oldName}/name`) answers 403 "Cannot rename folder", "Permission denied"; moving a message to a folder that does not exist answers 500; deleting a folder that
  holds a message answers 403; a reply (`POST .../reply`) answers 500 "Draft was not saved" and makes an empty draft (the reference lists it as a known issue); a forward answers 403, "a configuration error". Recall, the preferences and the
  purl calls are marked "Not implemented" in the reference.
- **Errors have their own shape.** The mailbox answers `{"error": ..., "errorDescription": ..., "errorCode": ...}`. The examples print the first two.

## In 2.0 under another name

| 1.4 | 2.0 |
| --- | --- |
| `/fileops` | `/fileOperations` |
| `/files` | `/files` (a file is changed with `PUT` or `PATCH` there) |
| `/shares` | `PUT /files/{path}` with `sharedDirectoryProperties`: [End User use case 06](../UseCases/06-sharing-a-folder/README.md) |
| `/myself/changePassword`, `/myself/resetPassword`, `/passwordReset`, `/passwordReset/requestLink` | `POST /myself/password` with `operation` change, reset or requestLink |
| `/myself/pollServerTime` | `GET /serverTime` |
| `/secretQuestion`, `/secretQuestions` | `/myself/secretQuestion`, `/secretQuestions` (the service answers 503 when it is switched off, in both) |
| `/transfers`, `/transfers/pull`, `/transfers/push`, `/transfers/folder-monitor` | `/transfers`, `POST /transfers/operations` |
| `/transfers/{id}/mdn/verify` | `POST /transfers/{id}/operations?operation=verifymdn` |

## Not covered

- **The address book writes** (`POST`, `PUT` and `DELETE /addressBook`). Tried: the create answered 403 "This operation is not allowed currently", with the collaboration on for the account and for the server (`AddressBook.AllowCollaboration`). It was not
  made to work. `GET /addressBook/count` and `/addressBook/myself` (the limits and whether collaboration is allowed) answer 200. In 2.0 the account's `addressBookSettings` is changed by the administrator: [Admin API 1.4](../../Admin/API%201.4/README.md).
- **The password policy** (`GET /passwordPolicy`): it answers the rules (`special`, `total`, `alpha`, `numeric`, `recentPasswords`, `minPasswordAge`) and has no 2.0 equivalent. No example yet.
- **The mailbox's anonymous links, the registration and the `auth` calls** (`/mailbox/messages/public`, `/mailbox/auth/...`): not tried.
- **The receipt and the data of a transfer** (`GET /transfers/{id}/mdn`, `/transferData`): not tried. The transfers need the account to be allowed the web service ("is not authorized to use the ST RESTful API" otherwise).
