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
| [01-authentication](01-authentication/README.md) | Getting in: Basic authentication on a single call, then the session (cookie jar and `csrfToken`), a write with the token, recovering from an expired session, and logging out. |
| [02-knowing-the-server](02-knowing-the-server/README.md) | What the server is and how it is set up, read-only: release, daemons, servers, a paged list, one setting among a thousand, login settings, open sessions. |

More are planned: onboarding a user and a partner, transfer sites, routes, finding a transfer, sessions and access, audit and
reporting, certificates and administrators.

## How a use case is organised

A folder named after the use case, numbered in the order to read it, a `README.md`, scripts numbered in the order they run, a
`00.run_all` that runs them all, a `99.cleanup_DELETE` that removes what they created (by exact `example_*` name), and
a test in `tests/checks/` and `tests/integration/checks/`. Every script says in its header which example of
`Admin/API 2.0/bash` it was copied from. The connection settings are those of `Admin/API 2.0/bash`
(`set_variables.local.sh`, which git ignores). `session.sh` is the one helper they share.
