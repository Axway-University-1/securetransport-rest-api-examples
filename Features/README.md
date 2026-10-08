# Features

Complete, end to end examples for individual SecureTransport features, one
folder per feature.

> **For test environments only.** These examples create accounts, transfer
> sites, routes and subscriptions, and run real transfers. Read the
> [Disclaimer](../README.md#disclaimer) before running anything.

The `Admin` and `EndUser` folders are organised by **object** (accounts,
applications, servers) and show one API call at a time. This folder is organised
by **solution**: each feature folder shows everything needed to set that feature
up, from start to finish.

## Available features

Grouped by the release in which the feature was introduced, newest first. A
feature works on that release and on every later one.

### 5.5-20260924

| Feature | What it does |
| ------- | ------------ |
| [Trigger route execution after a completed pull operation](trigger-route-after-completed-pull/) | Process all files from one pull as a single batch, in one route execution. |
| [Audit and report on billable transfers](audit-billable-transfers/) | Tell billable transfers from non-billable ones, with `GET /logs/transfers?isBillable=`, across six scenarios covering the billing rule, measured account by account: a partner to pull from, the test account, a partner to push to. |

## Version check

Every script in this folder starts by asking the server for its version with
`GET /version`. If the server is older than the release that introduced the
feature, the script prints `SKIPPED` and stops without changing anything. If the
version cannot be read at all, it stops with an error.

The version is written once, at the top of each script:

```bash
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
```

Versions are written `<major>.<minor>` or `<major>.<minor>-<YYYYMMDD>`, for
example `5.5-20260924`. A server that reports no date part is treated as the base
release, so it counts as older than every dated `5.5-...` update.

## Running an example

A feature connects with the same settings as the Admin examples
([Configuration](../README.md#configuration) in the main README) and also has a
settings file of its own, because it creates accounts and needs a password for them.
Copy `settings.local.example.sh` to `settings.local.sh` in the feature's folder
(`.bat` on Windows) and set the password it names: `BT_ACCOUNT_PASSWORD` for
`audit-billable-transfers`, `AR_ACCOUNT_PASSWORD` for
`trigger-route-after-completed-pull`. `settings.local.sh` and `state.local.sh`
(what a run has created, so that a clean-up can remove it) are git ignored.

```
cd Features/<feature-folder>
./00.run_all.sh                # the whole scenario, in order
./00.run_all.sh --cleanup      # the same, and everything it made is removed at the end
./00.run_all.sh ACCOUNT        # the same, with the test account named ACCOUNT
./99.cleanup_DELETE.sh [ACCOUNT]   # remove what an earlier run left
```

`00.run_all` runs the numbered scripts in order and checks what each one did; you can
also run a numbered script on its own. Each example comes as a `.sh` for bash and a
`.bat` for Windows, side by side.

Every example exits 1 when the server refuses a call, and `00.run_all` stops at the
first step that does. `99.cleanup_DELETE` exits 1 when it could not delete something,
says what is left and keeps `state.local.sh`; it is safe to run again.

When no account name is given, `00.run_all` checks that the new test account can use
its home folder, and moves to `<name>_2`, `_3` and so on when a home folder left over
from an earlier run belongs to another uid (see the feature's README).

Names: the settings of a feature have its own prefix (`AR_` for
`trigger-route-after-completed-pull`, `BT_` for `audit-billable-transfers`), and the
shared helpers in `Features/lib/` use theirs (`ar_*` functions, `AR_STATE_FILE`,
`AR_EU_*`, `EU_*`). They are not settings, except `EU_ACCOUNT`, `EU_ACCOUNT_PASSWORD`
and `EU_ENDUSER_PORT`: the helper reads those, and each feature's `settings.sh` sets
them from its own `AR_`/`BT_` ones. So the test account is read under several names
(the command line's `AR_RUN_ACCOUNT`/`BT_RUN_ACCOUNT`, then `AR_TEST_ACCOUNT`/
`BT_TEST_ACCOUNT`, then `EU_ACCOUNT`); each `settings.sh` says so.

## Adding a feature

1. Create a folder named after the feature, in lower case with hyphens, at the
   same level as the others. Do not put the release in the folder name.
2. Add a `README.md` to it: what the feature does, the release that introduced
   it, the scripts in run order, and anything to check first.
3. Number the scripts in the order they should be run. Write a `.sh` and a
   `.bat` for each, with the same name. Add `00.run_all` (the whole scenario, with
   `--cleanup`), `99.cleanup_DELETE` (removes what the others made), `settings.sh`
   with its `settings.local.example.sh` and `.bat` twins, and use the shared helpers
   in `Features/lib/` (`post_admin` and `admin_calls` for the Admin API, `enduser` for
   the End User API, `home_folder` for the test account's home) so a refused call
   stops the run: end a call with `|| exit 1`, and stop at the first one that fails.
4. Start every script with the version check above, using the release that
   introduced the feature.
5. Add the feature to the list in this file, under its release. Create a new
   release heading above the existing ones if needed.
6. Add tests: a `tests/checks/test_feature_<name>.sh` for the scripts (stub curl), the
   feature's bat twins in `test_feature_bat_twins.py`, and its version check in
   `test_feature_version_check.sh`. See [tests/README.md](../tests/README.md).
