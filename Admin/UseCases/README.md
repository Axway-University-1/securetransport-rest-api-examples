# Admin Use Cases

Complete, practical scenarios for the SecureTransport **administration API** (port 444, or 8444 on a non root
install), one folder per use case, the way [Features](../../Features/README.md) does it for what a release adds and
[the end user use cases](../../EndUser/UseCases/README.md) do it for the end user API.

> **For test environments only.** Read the [Disclaimer](../../README.md#disclaimer)
> before running anything.

The folder `Admin/API 2.0/bash` is organised by **resource** and shows one call at a time. This folder is for **scenarios**:
what an administrator actually does, from start to finish.

## The use cases

They are meant to be read in this order, each building on what the one before taught.

| Use case | What it teaches |
| -------- | --------------- |
| [01-authentication](01-authentication/README.md) | Getting in: Basic authentication on a single call, then the session (cookie jar and `csrfToken`), a write with the token, recovering from an expired session, logging out, and an API key for automation. |
| [02-knowing-the-server](02-knowing-the-server/README.md) | What the server is and how it is set up, read-only: release, daemons, servers, a paged list, one setting among a thousand, login settings, open sessions. |
| [03-onboard-a-user-account](03-onboard-a-user-account/README.md) | Taking on one end user: make the account with a home folder and an email address, read it back, change one thing with a PATCH, log in as the user on the End User API (and be refused with a wrong password), use the home folder, and delete the account. Why a home folder outlives its account. |
| [04-stopping-and-starting-servers](04-stopping-and-starting-servers/README.md) | Stopping and starting a protocol daemon for maintenance: write down the state, stop it (a confirmation word, `graceful` written out), wait for the status instead of the answer, start it, wait for it and its servers, compare with the start, and put back what a failure left stopped. Why a 200 can say no. |
| [05-changing-an-object](05-changing-an-object/README.md) | Changing what exists, with PATCH and PUT, on a throwaway account and route: how a PATCH is written for each type of value (text, number, true/false, list, nested object, null), read before and after every change; what the server converts and what it refuses; mistakes that answer 204; PUT of the whole object against a fragment that removes the steps; one server option saved, changed and put back exactly. |
| [06-lists-paging-and-fields](06-lists-paging-and-fields/README.md) | Read a list as a program must: what one answer holds (`returnCount`, `totalCount`, the page of 100 and what `limit=0` does), walk a long list by `limit` and `offset`, ask for fewer fields (and the one field that cannot be asked for), `HEAD` for 200, 404 and 405, the `Location` header of a new object, and a filter that changes `totalCount`. Makes five throwaway business units. |
| [07-usage-reporting](07-usage-reporting/README.md) | Report on use and invoice for it. Part 1, the whole server: the settings of the usage report, the active users (by name, not by account), the usage report `generateReport` (days, refusals, the summary against its days), the billable transfers of the log (`totalCount`, `account=`, the three values of `isBillable`), and the report against the log. Part 2, per business unit: three units, six accounts and 100 uploads, then the global total and a table of which unit consumed how much (`businessUnit=` on the transfer log), with the share of each and what is in no unit. |

Onboarding a user (03), stopping and starting servers (04), changing an object (05) reading lists (06) and usage reporting (07) are done. More are planned: onboarding a partner, transfer sites, routes, finding a transfer, sessions and access, audit and
reporting, certificates and administrators.

## How a use case is organised

A folder named after the use case, numbered in the order to read it, a `README.md`, scripts numbered in the order they run, a
`00.run_all` that runs them all, a `99.cleanup_DELETE` that removes what they created (by exact `example_*` name), and
a test in `tests/offline/checks/` and `tests/online/checks/`. Every script says in its header which example of
`Admin/API 2.0/bash` it was copied from. The connection settings are those of `Admin/API 2.0/bash`
(`set_variables.local.sh`, which git ignores). `session.sh` is the one helper they share.
