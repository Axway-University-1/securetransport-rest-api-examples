# 03 Onboard a user account

**Use case:** an administrator takes on one new end user: makes the account with its home folder and an email address, reads it back, changes one thing, proves that the user can log in and use the home folder,
and removes the account again.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`Admin/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores). Steps 04 and 05 talk to the **End User API**, which has its own port: add
> `export ST_ENDUSER_PORT=8443` (your port) to `set_variables.local.sh`. Without it the scripts use the admin port minus one, which is wrong on some installs.

## The examples

Run them in order (`00.run_all.sh` runs them all and ends with `99.cleanup_DELETE.sh`). Every script takes the name of the account as its first parameter, `example_onboard` when it is left out. The name **must start with
`example_`**: 06 and 99 delete by name, and this keeps them off a real account.

| Script | What it does | Copied from |
| ------ | ------------ | ----------- |
| `01.accounts_POST [NAME] [EMAIL]` | Makes the user account: home folder, a generated password (kept in `state.local.password`), an email address. An account that exists is not made again. | `Admin/API 2.0/bash/05.Accounts/02.accounts_POST.sh` |
| `02.accounts_GET [NAME]` | Reads it back (HEAD, then GET) and says what each field an administrator cares about means. The password is never returned. | `05.Accounts/03.accounts_name_HEAD.sh` and `04.accounts_name_GET.sh` |
| `03.accounts_PATCH [NAME] [EMAIL]` | Changes the email address with a JSON Patch `replace`, and reads it back. | `05.Accounts/06.accounts_name_PATCH.sh` |
| `04.enduser_login_GET [NAME]` | Logs in as the new user on the End User API (Basic authentication), then with a wrong password, on purpose: 401. | `EndUser/API 2.0/bash/03.Myself/01.myself_GET.sh` |
| `05.enduser_home_POST [NAME]` | As the user: makes a folder in the home, uploads a file, lists it. | `EndUser/API 2.0/bash/02.Files/02.files_name_POST_folder.sh` and `04.files_filepath_POST.sh` |
| `06.accounts_DELETE [NAME]` | Empties the home as the user, deletes the account (204), reads it (404), and says what stays. | `05.Accounts/07.accounts_name_DELETE.sh` |
| `99.cleanup_DELETE [NAME]` | Removes the account if it is still there, the state files and the administrator's session. Can be run twice. | |

`lib.sh` is the shared file: it loads `../session.sh` (the settings, the Admin session in `session.cookie.jar`, which git ignores) and has the checks of the name, the user id, the End User address and the helper
that empties a home folder.

## What to take from it

- A **user account** needs a name, a `homeFolder`, a `uid` and `gid`, and a password. The email address is what lets the user share folders (see [Moving files with the End User API](../../../Features/Guidance/moving-files-end-user-api.md)).
- The server answers `201` with the address of the new account in `Location`. It never returns the password afterwards.
- A **PATCH** changes only what it names; `replace` needs the field to exist ([Changing objects without breaking them](../../../Features/Guidance/changing-configuration.md)).
- Basic authentication works on the End User API without a session ([Authentication and sessions](../../../Features/Guidance/authentication-and-sessions.md)). A wrong password and an unknown user are answered the same way, so
  an attacker cannot tell which. Three wrong passwords lock the account, so step 04 sends one.
- **A home folder outlives its account.** Deleting the account does not delete `/home/NAME`: it stays on the server with the user id of the account that made it. A new account of the same name with *another* user id cannot create
  a folder directly in it (every such POST is 403 "Error occurred while creating file: null"). That is why 01 gives the same name the same user id every time (50000 to 59999, from the name), why 06 empties the home before it
  deletes, and why you should use a new name when you need a clean home. This use case does not make the second account to show it: it would leave an account with a broken home on your server.
- The Admin API has no file browsing. To look into a home, or to empty it, you go through the End User API as the user, which needs the user's password. That is the reason 01 keeps it in `state.local.password`.

## Tests

`tests/offline/checks/test_bash_admin_usecases.sh` runs every script against a stub `curl` and checks the call each one makes, its exit code and its messages. `tests/online/checks/64.admin_usecases_scripts.py` runs the whole use case on a real server with a throwaway account
and proves that nothing is left: no account, nothing in the home folder.
