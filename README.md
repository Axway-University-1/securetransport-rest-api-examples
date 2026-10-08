# SecureTransport-REST-API-Examples

> **These are examples, for test environments only.** Some of them change
> server configuration and stop or restart daemons and servers. Read the
> [Disclaimer](#disclaimer) before running anything.

## Table of Contents

1. [Introduction](#introduction)
2. [Disclaimer](#disclaimer)
3. [Axway University](#axway-university-training)
4. [Getting Started](#getting-started)
5. [Repository Layout](#repository-layout)
6. [Common Terminologies](#common-terminologies)
7. [OpenAPI](#openapi)
8. [HTTP Methods](#st-api-20-methods)
9. [What Is Covered](#what-is-covered)
10. [Features by Release](#features-by-release)
11. [License and Support](#license-and-support)

## Introduction
These examples are for REST API 2.0 of SecureTransport 5.5, and were verified on release 5.5-20260924. The older API 1.4 is also served by 5.5 but is not covered here.

This github project looks at use cases from a specific viewpoint. Many clients and Axway themselves have implemented mechanisms to on-board clients and file transfer flows in an automated manner using APIs, rather than the alternative method of manual setups via the admin GUI of ST. Automation brings a reduced risk of introducing errors and also assists in adhering to any standards enforced by the owning institution in naming standards, security profiles etc.
Many other automation tasks such as certificate expiry monitoring, configuration drift from baseline, etc are all possible via API based scripts or programs.
 
The examples here use the `curl` command from bash, the same calls as Windows batch files, and the python scripting language. It should be pointed out that **ANY** language that supports HTTPS Restful APIs can be used. Please also note that the commands shown are not the sole method you might want to use. Feel free to simplify or extend further what is shown as a guideline and starting point.


## Disclaimer

**Everything in this repository is an example, for use on test environments
only.**

- The scripts show how to call the SecureTransport REST API. They are not
  production tooling. They are provided AS IS, with no warranty, and are not
  covered by Axway support or by any Axway service level agreement.
- Run them only against a test or lab environment. Never run them directly
  against production.
- Several examples change the server itself, not only test objects: they
  modify server configuration options, stop, start and restart daemons and
  servers, update transfer sites, routes and subscriptions in bulk, and
  create, change or delete accounts. Read each script, and understand the
  consequences of every change it makes, before you run it.
- Before you use any example, or anything you build from one, on a production
  system, test it yourself on a test environment first, and confirm it does
  exactly what you expect there.

## Axway University Training

Login to Axway University using your Axway ID

https://university.axway.com/

And then you can access the learning plan for the SecureTransport REST API

https://university.axway.com/learn/learning-plans/77/securetransport-apis

## Getting Started

### Start with the guides

Three short guides save you working this out for yourself:

- **[Orientation](.claude/skills/st-api-orientation/SKILL.md)** — what is here,
  how it is laid out, and which example covers which task.
- **[Gotchas](.claude/skills/st-api-gotchas/SKILL.md)** — the non-obvious traps in
  the API and in scripting against it, collected from real debugging. Worth
  reading before your first call.
- **[Adding an example](.claude/skills/st-api-add-example/SKILL.md)** — the house
  style, if you plan to contribute.

### Check your clone works

```
./tests/run_all.sh
```

Takes about 5 seconds, needs no server and no credentials. See the
[tests Quick Start](tests/README.md) for what it checks and how to add a test
with your change.

### Prerequisites

| Tool | Needed for | Notes |
| ---- | ---------- | ----- |
| `curl` | every bash and bat example | Included with Windows 10 and later. |
| `jq` | most bash examples | Used to read and edit JSON responses. |
| `python3` | the python examples | Plus the `requests` library: `python3 -m pip install requests` |
| PowerShell | the bat examples | Used in place of `jq` to read JSON. |

### Configuration

None of the examples contain a server address or credentials. Each group of
examples reads them from a file that you create once and that git ignores, so
your details are never committed.

The same four names are used everywhere, so there is one set to learn:

| Variable | Meaning |
| -------- | ------- |
| `ST_SERVER` | The SecureTransport host, without the protocol or port |
| `ST_PORT` | The API port. See the table below. |
| `ST_USER` | The account to authenticate as |
| `ST_PASSWORD` | That account's password, in plain text |

Copy the example file for the examples you want to run and edit your copy:

| Examples | Copy this | To this |
| -------- | --------- | ------- |
| `Admin/API 2.0/bash` | `set_variables.local.example.sh` | `set_variables.local.sh` |
| `Admin/API 2.0/bat` | `set_variables.local.example.bat` | `set_variables.local.bat` |
| `Admin/API 2.0/python` | `config.example` | `config` |
| `EndUser/API 2.0/bash` | `set_variables.local.example.sh` | `set_variables.local.sh` |

For example:

```
cd "Admin/API 2.0/bash"
cp set_variables.local.example.sh set_variables.local.sh
$EDITOR set_variables.local.sh
```

The scripts then pick your values up on their own. There is nothing to
configure inside the individual examples, and nothing to edit in the committed
`set_variables.sh`, `set_variables.bat` or `config.example` files.

The password is always entered in plain text. Where the API expects a base64
encoded `user:password` pair, the scripts derive it for you, so there is no need
to run `base64` by hand.

### Which port?

| Examples | Non root install | Root install |
| -------- | ---------------- | ------------ |
| Admin | 8444 | 444 |
| EndUser | 8443 | 443 |

### How much an example changes

Every example's header has a `Risk:` line, the python programs' too, so you can
tell before running it what it may change on the server (the python ones are
held to it by `tests/checks/check_python_risk.py`, the others by
`tests/checks/check_risk_headers.py`):

| Risk | Meaning |
| ---- | ------- |
| `read` | Changes nothing: a GET or HEAD, a login or logout, a connection test. |
| `write` | Creates, changes or deletes objects: accounts, sites, routes, policies. |
| `config` | Changes a server-wide setting. Put it back afterwards. |
| `disruptive` | Stops a service, or cannot easily be undone: daemon and server operations, maintenance mode, the keystore password. Run these only on a lab of your own. |

To list them all, with the endpoint each one calls:

```
python3 tools/list_examples.py --table     # or without --table, as JSON
```

### Running an example

Each example is self contained and can be run directly:

```
cd "Admin/API 2.0/bash/01.Authentication"
./01.myself_POST.sh
```

If the configuration is missing, the scripts stop with a message telling you
which file to create rather than failing part way through a request.

## Repository Layout

```
Admin/API 2.0/          Administrator API, on the admin port
    bash/               curl examples, numbered by topic
    bat/                the same examples for Windows
    python/
        python3/         the python examples
        utils/           tools that work on an exported configuration XML
EndUser/API 2.0/
    bash/               end user API, on the user port
Features/               complete solutions, one folder per feature
tools/                  list_examples.py: every example, its endpoint and Risk
images/                 screenshots used by this README
```

The bash and bat examples are numbered by topic and, within a topic, by HTTP
method, so `04.Applications/02.applications_POST.sh` is the POST example for
applications. Reading a topic folder in order walks you through the full
create, read, update and delete cycle for that object.

The python examples are different in character: rather than demonstrating a
single call, each one is a small complete program for a real task, such as
baselining the server configuration or bulk updating accounts.

## Common Terminologies

The following table shows a list of terms and acronyms used throughout this project.

| Definition | Description |
| ---------- | ----------- |
| Admin API, EndUser API | The administrator's API (port 444, or 8444 on a non root install) and the smaller user level API (port 443, or 8443) |
| Advanced Routing | The SecureTransport feature that moves and transforms files by routes |
| Account | A user, service or template account; the owner of a home folder, sites and subscriptions |
| AS2, PeSIT, SFTP | File transfer protocols the server speaks (as listener and as client through a site) |
| Business unit | A group of accounts with its own settings and, optionally, a network zone |
| coreId | The id that ties the transfers of one file's journey through the server together |
| CSRF token | A header, returned by the login, that a session must send back on writes; see the gotchas |
| DMZ, zone, edge | A network zone and its edge server that sits between the outside and the core |
| EL | The Expression Language: `${...}` in route conditions, filters, rename patterns and login rules |
| ICAP | A protocol for passing files to a virus scanner |
| Route | A template, a simple or a composite route of Advanced Routing, run by a subscription |
| Site (transfer site) | A remote partner the server connects to, to pull or push files |
| Subscription | What links an account's folder to an application: a route or a trigger |
| ST | SecureTransport |
| MFT, TLS, JSON | Managed File Transfer, Transport Layer Security, JavaScript Object Notation |

## OpenAPI

SecureTransport provides an OpenAPI description of its APIs, with a Swagger UI on top of it, which allows you to explore them interactively.

In any browser enter as below, substituting your server’s IP and port used for the admin GUI. For example the default for a non root install would be: https://<SERVER>:8444/api/v2.0/docs/index.html for version 2.0 or https://<SERVER>:8444/api/v1.4/docs/index.html for version 1.4.

The above URLs all provide access to the ADMIN level APIS.  There is a smaller set of user level APIs available at the 8443 or 443 port.

You will be required to authenticate with an administrator username and password. Once authenticated, a screen as below will be seen.

![REST API 2.0 Open API](images/swagger_20.jpg "REST API 2.0 Open API")

Expanding any of the arrows will display the respective APIs along with available methods.

Selecting the GET /accounts for example will then open a window as below indicating all the possible parameters that might be used to select accounts from the system. Be careful of any API that is not a read or GET method.  PUTs, POSTs, DELETEs will all work if you enter the correct parameters and input data.

![GET /accounts](images/swagger_get_account.jpg "GET /accounts")

Note the ‘Try it out’ button. Select the button and you will now be able to use this API live.

The Open API provides a curl command equivalent that it is using to fetch the data. Notice also that a server response will be displayed showing the returned JSON data.

The HTTP success code of 200 is shown next to the response assuming all worked correctly. Finally, if you wish to download the response there is an option to download the output json to your PC.

A list answers at most 100 objects by default; ask for more with `limit` and `offset`, or change the default with the Server Configuration Option Webservices.EntriesPerPage.


## ST API 2.0 Methods

How the methods behave on SecureTransport. The details, and the surprises, are in the
[gotchas](.claude/skills/st-api-gotchas/SKILL.md); each was confirmed on a real server.

**GET** reads, and changes nothing. A list answers at most 100 objects, in no fixed order
unless you ask; page it with `limit` and `offset`.

**POST** creates an object (201, with its URL in the `Location` header: the created object
is not returned), or performs an operation: `POST .../operations?operation=X`, which
answers 200 or 202, so read the body, a 200 can carry a failure. `POST /myself` is a login.

**PUT** replaces the whole object (204). A field you leave out is reset, so send back the
object you read with your change applied. On a mail template a PUT creates it.

**PATCH** changes part of an object (204). The body is a JSON Patch: an array of
`{"op": "add" | "replace" | "remove", "path": "/field", "value": ...}`. A path addresses
an array element by its position (`/steps/1/...`), `-` appends, `replace` of a path the
object does not have is a 400 `Missing field`.

**DELETE** removes an object (204). A missing object may be a 400, not a 404.

**HEAD** is the cheap existence check: 200 or 404, no body (a few resources answer 405).

## What Is Covered

This project is a work in progress. The tables below describe what is in the
repository today, so that you can see at a glance whether the example you need
already exists.

### Admin API

| Topic | Endpoints | bash | bat |
| ----- | --------- | :--: | :-: |
| 01. Authentication | `/myself`, basic auth and cookie jar | 2 | 2 |
| 02. Introduction | `/version`, `/myself` | 6 | 6 |
| 03. Connect | `/daemons`, `/servers`, and their operations | 13 | 13 |
| 04. Applications | `/applications`, flow and maintenance types | 7 | 7 |
| 05. Accounts | `/accounts`, including PATCH from a file | 8 | 8 |
| 06. Transfer Sites | `/sites`, HTTP and SSH pull and push sites: list, check, read, replace, change and delete one by id, test a connection (saved or not) and list a remote folder | 11 | 11 |
| 07. Subscriptions | `/subscriptions`, Advanced Routing, with and without a trigger file, delete by id; check, read, replace and patch one by id; pull, clear the pull history and purge the folder; the other types (Basic, HumanSystem, MBFT, StandardRouter) | 13 | 13 |
| 08. Route Templates | `/routes`, template type | 1 | 1 |
| 09. Composite Routes | `/routes`, composite and simple types, Compress and Decompress steps, linked to a subscription, list, check, replace, patch a step, delete by id | 9 | 9 |
| 11. Certificates | `/certificates`, generate, import, export, signing requests | 14 | 14 |
| 12. Business Units | `/businessUnits`, units, their nesting, and why a delete is refused | 7 | 7 |
| 13. Configurations | `/configurations`: options, logging, database, Sentinel, login, archiving, external stores, S3 storage profiles | 47 | 47 |
| 15. Transfers | `/transfers/operations`, a pull on demand | 1 | 1 |
| 16. Transfer Logs | `/logs/transfers`, by account and status, billable transfers per day | 5 | 5 |
| 17. Access Policies | `/accessPolicies`, the embedded database's pg_hba.conf rules | 6 | 6 |
| 18. Account Setup | `/accountSetup`, an account with its sites, profiles and subscriptions in one call | 4 | 4 |
| 19. Address Book | `/addressBook/sources`, where end users' address books look people up | 5 | 5 |
| 20. Administrative Roles | `/administrativeRoles`, the roles and the menus they open | 7 | 7 |
| 21. Administrators | `/administrators`, administrators, locking them, and their API keys | 10 | 10 |
| 22. Denied Users | `/deniedUsers`, login names that may not log in, for good or for hours | 3 | 3 |
| 23. Events | `/events`, the tasks being processed now: list, read, delete a stuck one | 3 | 3 |
| 24. ICAP Servers | `/icapServers`, antivirus and DLP scan servers: add, change, switch on and off, and what a scan does to a transfer | 7 | 7 |
| 25. LDAP Domains | `/ldapDomains`, directories users can be looked up in: add, change, remove, and test a connection | 8 | 8 |
| 26. Login Restriction Policies | `/loginRestrictionPolicies`, rules that allow or deny logins by address: policies, rules, business units | 9 | 9 |
| 27. Audit Logs | `/logs/audit`, who changed what, and when: list, read, a refused edit, CSV export | 4 | 4 |
| 28. Server Logs | `/logs/server`, what the servers wrote: search, read, CSV export | 3 | 3 |
| 29. Mail Templates | `/mailTemplates`, the XHTML files the notification e-mails are built from: list, add, replace, read, delete | 6 | 6 |
| 30. Route Steps Metadata | `/routeStepsMetadata`, the route step types the server knows, how a step names one and the smallest step of each: list (read only) | 1 | 1 |
| 31. Route Steps Charsets | `/routeStepsCharsets`, the character sets a route step may name, and a check of a step against them: list (read only) | 1 | 1 |
| 32. Sessions | `/sessions`, the sessions open now: list, read one, end one (a client is disconnected), and the bandwidth and user class statistics | 5 | 5 |
| 33. Statistics Summary | `/statisticsSummary`, the usage report: the transfers in and out for each day of a period, the users who have logged in, and a test of the connection to the Amplify Platform it is sent to (read only) | 3 | 3 |
| 34. Transaction Manager | `/transactionManager`, the status of the Transaction Manager (read only), and `/transactionManager/operations`, the stop: server wide, no start to undo it, needs a confirmation word on the command line (disruptive, written from the reference and not run on a server) | 2 | 2 |
| 35. Transfer Profiles | `/transferProfiles`, the PeSIT profiles of an account that say which file to send, what to call the file received and how it is labelled: list, create, HEAD, read, replace, patch and delete | 7 | 7 |
| 36. User Classes | `/userClasses`, the classes that decide which class an account is in when it logs in (a user name pattern, a type, a membership expression, an order): list, create, HEAD, read, replace, patch and delete | 7 | 7 |
| 37. Zones | `/zones`, the network (DMZ) zones with their edges, protocols and proxies, and the business units that name one: list, create, HEAD, read, replace, patch and delete | 7 | 7 |
| 90. End To End Acknowledgment | `/logs/transfers`, PeSIT ACK and NACK | 2 | 2 |

Every bash example has a bat equivalent, so Windows users can follow the same
path through the material. Where the bash examples use `jq`, the bat examples
use PowerShell to do the same job.

### EndUser API

| Topic | Endpoints | bash |
| ----- | --------- | :--: |
| 01. Authenticate | `/myself`, login and logout | 2 |
| 02. Files | `/files` and `/fileOperations`: list, with paging, sorting, metadata and glob patterns; create a folder; upload, with an MD5 check; download; rename; share and unshare; delete | 15 |
| 03. Myself | `/myself`, `/myself/password`, `/myself/passwordExpired`, `/myself/secretQuestion`, `/secretQuestions`, `/myself/addressBook`: the account, password change and reset, secret questions, the address book | 10 |
| 04. File Operations | `/fileOperations`: MD5 checksum, an operation's state, chunked and multipart uploads, cancel | 5 |
| 05. Transfers | `/transfers`, `/transfers/operations`, `/transfers/pullSummary`: the user's transfer log, pull, push, folder monitor, pull summary, AS2 receipt check | 7 |
| 06. Server Time | `/serverTime` | 1 |

Every resource of the EndUser API 2.0 reference has an example. All of them
were run against a real server except three, which say so in their own header:
the password reset pair (`03.Myself/04` and `05`), which need a real reset
email, and `05.Transfers/07`, which needs an AS2 transfer.

Where the EndUser API behaves differently from what you might expect,
confirmed against a real server:

- **Writes do not need the `csrfToken`.** The login answers with one, but a
  POST, PUT, PATCH or DELETE succeeds without it: the session cookie is enough.
- **Changing the password ends the session.** The next call with the same
  cookie answers 401. Log in again with the new password, as
  `03.Myself/03.myself_password_POST_change.sh` does.
- **`/transfers` returns a plain list**, not the `{resultSet, result}` envelope
  the Admin API uses. So do `/myself/addressBook` and `/secretQuestions`.
- **A wrong `Content-MD5` gives a bare 500**, "Error while uploading file", with
  no word about the checksum. File Tracking logs the upload as Failed.
- **A file operation's status describes the operation, not the file.** An
  Upload stays `IN_PROGRESS` after its last chunk, though the file is whole.
  Check the file itself, with `02.Files/10.files_filepath_GET_metadata.sh`.
- **`/serverTime` writes the offset as `+0300`**, not with the `Z` the API
  reference shows. Parse the offset, as `06.ServerTime/01.serverTime_GET.sh` does.

### Python

The python examples are whole programs for real maintenance tasks, rather than
single calls. They are CSRF aware, as required from the 20230525 release onwards:
each logs in once and sends the `csrfToken` of the login on every later call, the
logout included. The lab accepts a write without it, which hid a script that
forgot, so `tests/checks/test_python_scripts_run.py` runs every one of them as a
whole against a fake server that refuses such a write. The same test checks the
exit codes: a failure exits 1 (a bad argument 2), never 0, and a connection error
or a timeout always ends the script.

| Script | What it does |
| ------ | ------------ |
| `stBuildFullTestAccount.py` | Onboards one account end to end: account, certificate, transfer site, routes and subscription. The best place to start if you are automating onboarding. |
| `stBuildTestAccounts.py` | Creates accounts in bulk, using multiprocessing. A dry run unless `--apply`; the prefix and the number are arguments. |
| `stDeleteTestAccounts.py` | Deletes the user accounts whose name starts with a prefix (`ZZ`, what `stBuildTestAccounts.py` makes), in bulk. Lists them and deletes nothing unless `--apply`. |
| `stGetAccountsAfterDate.py` | Lists accounts created after a given date. |
| `stUpdateAllAccounts.py` | Scans every template account and updates a field. Uses certificate based authentication rather than basic auth. |
| `stUpdateAllRoutes.py` | Scans every simple route and patches a field on the route, or a field inside one of its steps. |
| `stUpdateRouteWithPut.py` | Reads a route, changes it and writes the whole object back. Inserts steps, links a simple route into a composite, or attaches a route to a subscription. |
| `stUpdateAllSubscriptions.py` | Scans every subscription and patches a set of fields. |
| `stUsersPerSharedFolder.py` | Reports which accounts have access to each shared folder, by joining applications and subscriptions. Read only. |
| `stReplaceSites.py` | Scans SSH transfer sites and updates their cipher suites. |
| `stCertificateExpiry.py` | Counts the certificates and reports the ones that have expired or are about to. Read only. |
| `stBillableTransfers.py` | Counts the billable transfers per day, for every account or for one. Needs 5.5-20260924 or later. Read only. |
| `stGetPrivateCert.py` | Exports a certificate and its private key by ID, as a PKCS#12 file readable by its owner only. The password for the file comes from the environment or a prompt, never from the command line or the URL. |
| `stAddLoginRestrictionRule.py` | Adds a rule to an existing login restriction policy. |
| `stConfigScan.py` | Baselines the server configuration (as JSON) and reports drift from the baseline on later runs, in both directions. Useful after a patch. |
| `stGraceful.py` | Gracefully drains and shuts down a core and edge pair, **the Transaction Manager included, which the API cannot start again**. Stops nothing without `--yes`, and not the Transaction Manager unless every daemon went down in time. |

The scripts that create, change or delete many objects at once —
`stUpdateAllRoutes.py`, `stUpdateAllSubscriptions.py`, `stUpdateRouteWithPut.py`,
`stUpdateAllAccounts.py`, `stReplaceSites.py`, `stBuildTestAccounts.py` and
`stDeleteTestAccounts.py` — are a dry run by default: they say what they would send
and send nothing. Read that output, then give `--apply` (or set `dryRun` to `False`
in the configuration section) to let them write. `stGraceful.py` has no dry run to
fall back on: it needs `--yes` and does nothing without it.

Optional keys of the `config` file (see `config.example`): `st_ca_bundle` or
`st_verify=yes` turn on the check of the server's certificate, which the examples
leave off by default so that a lab with a self signed certificate works.

`utils` holds two tools whose input is an exported `systemConfiguration.xml`
rather than the live API:

| Script | What it does |
| ------ | ------------ |
| `stCompareExportedConfigurations.py` | Compares two exported configurations and reports the options whose value differs, and the options present in only one of them. Useful when you have the exports but no access to the system. |
| `processSystemConfig.py` | Extracts the user classes from an export and converts their membership expressions from the 5.2.1 format to the 5.5 format. Writes the result as XML, and can create the user classes on a target server through the API when `createOnTarget` is set. |

Export the configuration from the GUI, then take the XML out of the zip it
produces:

```
unzip -j export_configuration.zip systemConfiguration.xml -d /home/axway/api
```

### Not yet covered

These areas of the API do not have examples yet. Contributions are welcome, and
the list doubles as a rough roadmap.

- Site Templates (the lab has no Connect:Direct, so every create is refused)
- Cluster Services (not planned: the examples are written against a standalone server)

Only the following remain uncovered:
- **siteTemplates:** requires Connect:Direct protocol, not available on this lab
- **clusterServices** and cluster-only configuration operations: standalone lab
- Parts of **configurations:** Oracle-only `database/{componentType}`, database connection, replication


## Features by Release

New SecureTransport releases add features that are easier to learn as a complete
solution than as a list of API calls. Those live in [Features](Features/), one
folder per feature, with the same examples in bash and as Windows batch files.

The folders are organised by feature, so that a feature is easy to find. The
[Features index](Features/README.md) lists them grouped by the release that
introduced them, so you can see which ones your version supports. Every script
also checks the server version with `GET /version` before it does anything, and
skips itself on a release that is too old.

| Release | Feature |
| ------- | ------- |
| 5.5-20260924 | [Trigger route execution after a completed pull operation](Features/trigger-route-after-completed-pull/) |
| 5.5-20260924 | [Audit and report on billable transfers](Features/audit-billable-transfers/) |

## License and Support

These examples are published under the Apache License 2.0. See [LICENSE](LICENSE).

The included software is provided AS IS, with no implied or expressed warranty,
and is not covered by any Axway service level agreement. It is intended to
illustrate the API rather than to be run unmodified against a production
system. Take a backup before running anything that writes, and test the result
afterwards. Note in particular that several examples create, modify or delete
objects, and that `python3/stDeleteTestAccounts.py` deletes accounts in bulk.