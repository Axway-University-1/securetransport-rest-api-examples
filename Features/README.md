# Features

Complete, end to end examples for individual SecureTransport features, one
folder per feature.

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

Features use the same connection settings as the Admin examples, so there is
nothing extra to configure. If you have not done that yet, see
[Configuration](../README.md#configuration) in the main README.

```
cd Features/<feature-folder>
./01.<name>.sh
```

Each example comes as a `.sh` for bash and a `.bat` for Windows, side by side.

## Adding a feature

1. Create a folder named after the feature, in lower case with hyphens, at the
   same level as the others. Do not put the release in the folder name.
2. Add a `README.md` to it: what the feature does, the release that introduced
   it, the scripts in run order, and anything to check first.
3. Number the scripts in the order they should be run. Write a `.sh` and a
   `.bat` for each, with the same name.
4. Start every script with the version check above, using the release that
   introduced the feature.
5. Add the feature to the list in this file, under its release. Create a new
   release heading above the existing ones if needed.
6. Add tests. See [CLAUDE.md](../CLAUDE.md).
