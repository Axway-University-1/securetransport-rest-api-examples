# Use Cases

Complete, practical scenarios for the SecureTransport **end user API** (port 8443,
or 443 on a root install), one folder per use case, the way [Features](../../Features/README.md)
does it for the administrator API.

> **For test environments only.** Read the [Disclaimer](../../README.md#disclaimer)
> before running anything.

The folder `EndUser/API 2.0/bash` is organised by **resource** (files, the account,
transfers) and shows one call at a time. This folder is for **scenarios**: what a user
or a partner actually does, from start to finish, for example uploading a set of files
and checking what became of them.

## The use cases

They are meant to be read in this order, each building on what the one before taught.

| Use case | What it teaches |
| -------- | --------------- |
| [01-authentication](01-authentication/README.md) | Getting in: Basic authentication on a single call, then the session (cookie jar and csrfToken), recovering from an expired session, and logging out. |
| [02-knowing-yourself](02-knowing-yourself/README.md) | What the server says about the account: `/myself` whole and narrowed with jq, password expiry, the server's clock, the address book. |
| [03-files-and-folders](03-files-and-folders/README.md) | One story: create a folder, upload, list, read, details, update, rename, delete the file and the folder. |
| [04-larger-files](04-larger-files/README.md) | Trust a transfer: Content-MD5 on the way in, an MD5 asked for afterwards, uploads in pieces, by operation, and in bulk. |
| [05-checking-transfers](05-checking-transfers/README.md) | What became of the files: the transfer list, filters, one transfer, a summary. |
| [06-sharing-a-folder](06-sharing-a-folder/README.md) | Let another user work in a folder: share it with `read`, `write` or `full`, see how, change the type of share, stop sharing. Needs an account with an e-mail address and a user to share with, given as a parameter. |
| [07-secret-questions](07-secret-questions/README.md) | Choose and set a secret question (the answer is a parameter), read it back, see a refused change, and what can be done about removing one. Needs the service switched on by an administrator. |

## How a use case is organised

Follow the conventions of [Features](../../Features/README.md): a folder named after the
use case in lower case with hyphens, a `README.md` that says what it does and in which
order to run the scripts, scripts numbered in the order they run, a `00.run_all` that runs
them all, a `99.cleanup_DELETE` that removes every object they created, and a test for
each script in `tests/offline/checks/`. The connection settings are the ones of
`EndUser/API 2.0/bash` (`set_variables.local.sh`, which git ignores).
