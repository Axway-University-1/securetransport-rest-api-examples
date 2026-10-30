# 08 Lists and paging

**Use case:** read a list as an end user: the files of a folder, your transfers, your address book. They look alike and are not: each has its own shape, its own rules for `limit` and `offset`, and none of them has a count.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`EndUser/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

The Admin API has the same job and different rules (a `resultSet` with a `totalCount`, a page of 100, `fields=`):
[06 Lists, paging and fields](../../../Admin/UseCases/06-lists-paging-and-fields). Read both when you write a client that serves administrators and end users.

Step 01 makes a folder `example_uc_lists` in your home folder with a few small files, so that there is something to page through. `99.cleanup_DELETE.sh` removes them by name. Everything else only reads.
`/transfers` needs an account that may use the transfers web service (`transfersWebServiceAllowed` in `GET /myself`, set by an administrator): without it step 03 stops with exit 3 and `00.run_all.sh` skips it, and 05 and 06 say they leave it out.

## The examples

Run them in order (`00.run_all.sh [COUNT] [LIMIT]` runs them all and ends with `99.cleanup_DELETE.sh`). The scripts take their input as parameters, and say what they need when it is wrong, before any call.

| Script | What it does | Copied from (`EndUser/API 2.0/bash`) |
| ------ | ------------ | ------------------------------------ |
| `01.files_POST_location [COUNT]` | Makes the folder and COUNT files (1 to 20, default 7), shows the `Location` of each (a new folder has none) and reads the first back by it. | `02.Files/02.files_name_POST_folder.sh` and `04.files_filepath_POST.sh` |
| `02.files_GET_list [LIMIT]` | The list of the folder: an object with no count, every entry when you give no limit, a walk by `limit` and `offset` that ends on a short page, `limit=0`, the sort, two limits the server cannot use. | `02.Files/01.files_GET.sh` and `09.files_GET_query.sh` |
| `03.transfers_GET_list [LIMIT]` | `/transfers`: a plain array, newest first, a default page of 100 that is not a cap, `limit=0`, and the two limits it refuses. Exit 3 when the account may not use it. | `05.Transfers/01.transfers_GET.sh` |
| `04.addressBook_GET` | `/myself/addressBook` takes a limit and an offset; `/secretQuestions` takes none. Both are plain arrays. | `03.Myself/08.myself_addressBook_GET.sh` and `07.SecretQuestions/01.secretQuestions_GET.sh` |
| `05.fields_not_offered` | `fields=` is not refused and has no effect: the entry has the same fields with it and without it. | |
| `06.counting_without_totalCount [PAGE_SIZE]` | Counts a list that has no count, by reading pages and stopping at a short one: the files of the folder and the transfers. | |
| `99.cleanup_DELETE` | Deletes the files `lst_NN.txt` of the folder, then the folder, and ends the session. Can be run twice. | |

`lib.sh` is the shared file: it loads `../session.sh` (the settings, the session in `session.cookie.jar`, which git ignores, `st_session` and `st_enc`), names the folder, and has the checks of the parameters and the one call that every read makes.

## What to take from it

Tried on SecureTransport 5.5-20260924 (the End User port is 8443 on the lab):

| | `GET /files/FOLDER` | `GET /transfers` | `GET /myself/addressBook` | `GET /secretQuestions` |
| - | ------------------- | ---------------- | ------------------------- | ---------------------- |
| The answer is | an object: `files`, `self` (and `parent` below the home) | a plain array | a plain array | a plain array of text |
| A count | none | none | none | none |
| No `limit` gives | **every entry**: a folder of 105 returned 105 | **100**: the default page | all of them (5 on the lab) | all of them (9) |
| `limit=0` gives | **nothing** | the default page, 100 | | |
| `limit` above 100 | honoured | honoured: `limit=500` returned 105 of 105 | | no effect: all 9 |
| `limit=-1` | **not refused**: every entry | 400 `Parameter should be a positive number or 0.` | | |
| `limit=abc` | **404** `HTTP 404 Not Found` | **404** `HTTP 404 Not Found` | | |
| `offset` | works: `limit=10&offset=100` on 105 returned the last 5 | works | works | |
| `fields=` | ignored | ignored | | |
| Sort | `sortBy=fileName` or `size` (tried), `lastModifiedTime` (the reference), `order=ASC` or `DESC`; an unknown `sortBy` is ignored (200) | newest first | | |

Three things follow.

- **No count, so the end is a short page.** Ask for `limit=N`, add what you got to the `offset`, and stop at the first page with fewer than N entries. A list that is an exact multiple of N costs one more call, which returns nothing (02 shows it).
  To count a list you read it (06). To count a long history, the Admin API has a `totalCount` (`GET /logs/transfers`), and an end user does not.
- **A `limit` of 0 does three things.** It is the default page on the Admin API and on `/transfers`, and it returns nothing on the file list. Never use 0 for "no limit". A negative `limit` is refused on `/transfers` and accepted on the file list, and a `limit`
  that is not a number is 404 on both, not 400, so a client that checks for 400 will not see it. Send only a `limit` that you checked.
- **`fields=` does not narrow the answer.** `GET /myself?fields=name` returns the whole account, and `/transfers?fields=filename` returns all 19 fields. It is not an error, so a client that relies on it does not notice. Do not use it to make an answer small;
  read the fields you need from the whole entry. On the Admin API `fields=` works ([06](../../../Admin/UseCases/06-lists-paging-and-fields)).

**The `Location` header.** A `POST` that creates answers 201 with no body, and the address of the new object is in `Location`. For an upload, it is the path with every `/` written `%2F`: `.../files/%2Fexample_uc_lists%2Flst_01.txt`.
Use it as it is. **A new folder answers 201 with no `Location` at all**, so build a folder's address yourself. A file that is already there is replaced (201, and the same `Location`).

**The same thing has two names between the list and the single object.** The transfer in the list has `filename`, `filesize` and `direction`; the same transfer read by its id has `file`, `size` and `transferType`. Read the list with the names of the list.

## Tests

`tests/offline/checks/test_bash_enduser_usecase_08.sh` runs every script against a stub `curl` and checks the call each one makes (the query it builds, the body of a POST, the walk), its messages and exit codes.
`tests/online/checks/74.enduser_usecase_lists_and_paging.py` runs the whole use case on a real server with throwaway accounts (one that may use the transfers web service and one that may not), checks the shapes and the limits against what this README says, and proves that nothing is left.
