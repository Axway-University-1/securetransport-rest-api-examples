---
name: st-api-orientation
description: Orient yourself in the SecureTransport REST API 2.0 examples repository and find the right example fast. Use this skill whenever someone asks where an example lives, which script does X, how to configure or run the examples, what the repository covers, what is missing, or how the bash, bat and python trees relate to each other. Also trigger on "how do I call the ST API to do X", "is there an example for Y", "how do I authenticate", "which port", "how do I set my server and credentials", or when a newcomer to this repository asks how to get started. Read this before exploring the tree by hand.
---

# SecureTransport API examples: orientation

This repository holds working examples of the **Axway SecureTransport REST API 2.0**,
in three languages, for two API surfaces. This skill tells you what is here and how
to find the right example, so you do not have to read the tree to find out.

Two companion skills carry the rest of the knowledge:

- **st-api-gotchas** — the non-obvious API and scripting traps. Read it before
  writing or debugging any call. It is the highest-value file in this pack.
- **st-api-add-example** — the house style, for when you add an example.

## The two API surfaces

| Tree | Port (non-root / root) | What it covers |
| ---- | ---------------------- | -------------- |
| `Admin/API 2.0/` | 8444 / 444 | The full administrator API |
| `EndUser/API 2.0/` | 8443 / 443 | The small end-user API: login and file transfer |

Getting the port wrong is the most common first-run failure. The admin API is
not served on the user port and vice versa.

## Layout

```
Admin/API 2.0/
    bash/     99 curl examples, numbered by topic
    bat/      91 of them, for Windows
    python/
        python3/   16 complete programs for real maintenance tasks
        utils/     2 tools that read an exported systemConfiguration.xml
EndUser/API 2.0/
    bash/     40 examples: every resource of the EndUser API reference - files,
              file operations, the account and password, the address book,
              the user's own transfers, the server time
```

`bash` and `bat` are kept at **exact parity** — every bash example has a bat
twin with the same name and the same behaviour, with one deliberate
exception: `bash/14.ExpressionLanguage/` (Expression Language exercises) was
scoped to bash and python3 only when it was added, and has no bat twin. If
you change any other bash example, change its bat twin too.

## How to find an example

The bash and bat examples are named `NN.resource_METHOD.ext`, numbered by topic
and then by HTTP method. So `04.Applications/02.applications_POST.sh` is the POST
example for applications. Reading a topic folder in order walks the full
create, read, update, delete cycle for that object.

| I want to... | Look at |
| ------------ | ------- |
| Authenticate, basic auth or a cookie jar session | `bash/01.Authentication/` |
| Check the version, or read and change my own account | `bash/02.Introduction/` |
| Start or stop daemons and protocol servers | `bash/03.Connect/` |
| Create flow or maintenance applications | `bash/04.Applications/` |
| Create, read, update, delete accounts | `bash/05.Accounts/` |
| Send a PATCH body from a file | `bash/05.Accounts/06.accounts_name_PATCH_with_file.sh` |
| Create, list or delete a transfer site, including SSH pull and push sites that rename | `bash/06.TransferSites/` |
| Subscribe a folder to Advanced Routing, with or without a trigger file | `bash/07.Subscriptions/` |
| Create route templates in bulk | `bash/08.RouteTemplates/` |
| Create a composite route, with or without an extension | `bash/09.CompositeRoutes/` |
| Compress or decompress in a route, then send to a partner | `bash/09.CompositeRoutes/03.routes_POST_simple_compress.sh`, `04.routes_POST_simple_decompress.sh` |
| Link a composite route to a subscription, so it runs on what arrives | `bash/09.CompositeRoutes/05.routes_POST_composite_subscription.sh` |
| Create a business unit | `bash/12.BusinessUnits/` |
| Change a Server Configuration Option | `bash/13.Configurations/` |
| Set up usage reporting to the Axway Platform | `bash/13.Configurations/02.configurations_PATCH_UsageReporting.sh` |
| Start a pull from a partner on demand | `bash/15.Transfers/` |
| Read the transfer log, or count billable transfers per day | `bash/16.TransferLogs/` |
| Correlate PeSIT transfers and send ACK or NACK | `bash/90.EndToEndAcknowledgment/` |
| Use SecureTransport's Expression Language in a route condition, a file filter, a rename pattern or a login restriction rule | `bash/14.ExpressionLanguage/` (also in `python/python3/14.ExpressionLanguage/`) |
| Upload or download files as an end user | `EndUser/API 2.0/bash/02.Files/` |
| Create a folder, or upload to a chosen path, as an end user, with the csrfToken | `EndUser/API 2.0/bash/02.Files/02.files_name_POST_folder.sh`, `08.fileOperations_POST_upload.sh` |
| List files with paging, sorting, metadata or a glob; rename; share a folder | `EndUser/API 2.0/bash/02.Files/` 09 to 15 |
| Read the account, change or reset the password, use the address book, as an end user | `EndUser/API 2.0/bash/03.Myself/` |
| Checksum a file on the server, upload in chunks, cancel an upload | `EndUser/API 2.0/bash/04.FileOperations/` |
| Pull, push or run a folder monitor as an end user, and read the user's own transfer log | `EndUser/API 2.0/bash/05.Transfers/` |

The numbering has gaps (10 and 11 are absent). Those topics have no examples yet.

## The python examples are a different kind of thing

The bash and bat examples each demonstrate one call. The python examples are
whole programs for jobs you would actually run against an estate:

| Script | Job |
| ------ | --- |
| `stBuildFullTestAccount.py` | Onboard one account end to end: account, certificate, site, routes, subscription. Start here if you are automating onboarding. |
| `stBuildTestAccounts.py` / `stDeleteTestAccounts.py` | Create or delete accounts in bulk, using multiprocessing |
| `stGetAccountsAfterDate.py` | List accounts created after a date |
| `stUpdateAllAccounts.py` | Update a field on every template account. Uses **certificate** auth, not basic auth |
| `stUpdateAllRoutes.py` | Patch a field on every simple route, or a field inside one of its steps |
| `stUpdateRouteWithPut.py` | Read, change and write back a whole route: insert steps, link a simple route into a composite, attach a route to a subscription |
| `stUpdateAllSubscriptions.py` | Patch fields on every subscription |
| `stUsersPerSharedFolder.py` | Report which accounts can reach each shared folder |
| `stReplaceSites.py` | Update the cipher suites on SSH transfer sites |
| `stCertificateExpiry.py` | Count certificates and report expired and expiring ones |
| `stBillableTransfers.py` | Count billable transfers per day, for every account or one. Needs 5.5-20260924 or later |
| `stGetPrivateCert.py` | Export a certificate by ID. Needs `requests_toolbelt` |
| `stAddLoginRestrictionRule.py` | Add a rule to a login restriction policy |
| `stConfigScan.py` | Baseline the server config, then report drift. Useful after a patch |
| `stGraceful.py` | Drain and shut down a core plus edge pair |
| `utils/stCompareExportedConfigurations.py` | Diff two exported `systemConfiguration.xml` files |
| `utils/processSystemConfig.py` | Convert 5.2.1 user classes to the 5.5 expression format, optionally creating them |

**The four scripts that change many objects at once — `stUpdateAllRoutes.py`,
`stUpdateAllSubscriptions.py`, `stUpdateRouteWithPut.py` and
`utils/processSystemConfig.py` — default to a dry run.** Leave that on for the
first run and read the output. They tell you exactly what they would send.

## Configuration: four variables, one name everywhere

Nothing in the repository contains a server address or a credential. Every tree
reads the same four names from a file that git ignores:

`ST_SERVER`, `ST_PORT`, `ST_USER`, `ST_PASSWORD`

Copy the example, fill in your copy:

| Tree | Copy | To |
| ---- | ---- | -- |
| `Admin/API 2.0/bash` | `set_variables.local.example.sh` | `set_variables.local.sh` |
| `Admin/API 2.0/bat` | `set_variables.local.example.bat` | `set_variables.local.bat` |
| `Admin/API 2.0/python` | `config.example` | `config` (keys in lower case) |
| `EndUser/API 2.0/bash` | `set_variables.local.example.sh` | `set_variables.local.sh` |

Two things worth knowing:

- **The password goes in as plain text.** Where the API wants a base64
  `user:password` pair, the scripts derive it. Never hand-encode it.
- The committed `set_variables.sh` and `set_variables.bat` hold placeholders and
  load your `.local` file over the top. **Do not edit the committed files** — that
  is how credentials end up in a commit.

If configuration is missing, the scripts stop with a message naming the file to
create, rather than failing halfway through a request.

## Running an example

Every script resolves its own directory, so it runs from anywhere:

```
./Admin/API\ 2.0/bash/01.Authentication/01.myself_POST.sh
```

## Prerequisites

| Tool | Needed for |
| ---- | ---------- |
| `curl` | every bash and bat example |
| `jq` | the bash examples that read, build or edit JSON. Each one says so in its header |
| PowerShell | the bat examples, in place of `jq` |
| `python3` plus `requests` | the python examples |
| `requests_toolbelt` | `stGetPrivateCert.py` only |

## What is not covered

Transfer operations other than a pull, sessions, events and statistics summary;
transfer profiles and route step charsets or metadata; site templates, address
book, account setup; administrators, administrative roles, user classes; access
policies; cluster services, ICAP servers, LDAP domains, zones; mail templates.

Changing routes and subscriptions that already exist, certificates and the
transaction manager are covered by the **python** examples but not yet by bash
or bat.
Login restriction policies and EL route conditions are the exception - both
are covered in bash too, in `14.ExpressionLanguage` (see the table above),
alongside the python3 twin of the same folder.

## Exploring the live API

The Open API page lists every endpoint and lets you try it:

```
https://<SERVER>:8444/api/v2.0/docs/index.html
```

It is the authority on field names, which vary between releases. When an example
disagrees with it, believe the Open API page for your version.

By default a list call returns at most 100 objects. That limit is the
`Webservices.EntriesPerPage` Server Configuration Option.
