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

This folder is empty for now; the first use cases will be added here.

## How a use case is organised

Follow the conventions of [Features](../../Features/README.md): a folder named after the
use case in lower case with hyphens, a `README.md` that says what it does and in which
order to run the scripts, scripts numbered in the order they run, a `00.run_all` that runs
them all, a `99.cleanup_DELETE` that removes every object they created, and a test for
each script in `tests/checks/`. The connection settings are the ones of
`EndUser/API 2.0/bash` (`set_variables.local.sh`, which git ignores).
