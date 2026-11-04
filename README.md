# SecureTransport-REST-API-Examples

> **These are examples, for test environments only.** Some of them change
> server configuration and stop or restart daemons and servers. Read the
> [Disclaimer](#disclaimer) before running anything.

## Table of Contents

1. [Introduction](#introduction)
2. [Disclaimer](#disclaimer)
3. [Axway University](#axway-university-training)
4. [Getting Started](#getting-started)
5. [Where to find things](#where-to-find-things)
6. [License and Support](#license-and-support)

## Introduction
These examples are for REST API 2.0 of SecureTransport 5.5, and were verified on release 5.5-20260924. The older API 1.4 is also served by 5.5. Only what it can do and 2.0 cannot is covered, in [Admin/API 1.4](Admin/API%201.4/README.md).

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
  style, if you plan to contribute. (The fourth skill in that folder, the procedure for covering a new API resource, is for contributors too: see [CONTRIBUTING.md](CONTRIBUTING.md).)

For how the API behaves when you use it, such as the date formats or sessions, read the [Guidance](Features/Guidance/README.md) guides. For doing it step by step (usage reporting, stopping a daemon,
changing an object, reading lists, moving files), run the [Admin](Admin/UseCases/README.md) and [End User](EndUser/UseCases/README.md) use cases.

### Check your clone works

```
./tests/offline/run_all.sh
```

Takes up to 5 minutes, needs no server and no credentials. See the
[tests Quick Start](tests/README.md) for what it checks and how to add a test
with your change. To test your own scripts the same way, see [Testing your own scripts](tests/README.md#testing-your-own-scripts).

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

Two more settings are optional, and only the `Admin/API 2.0` bash and bat
examples read them. Some of those examples need an account that already exists,
and four name the partner's SSH port. They use `john` and `8022`; if your server
has no `john`, or its SSH port is not 8022, set these instead of editing the
examples. Leave them out and nothing changes. An argument given to an example
still wins over them.

| Variable | Meaning | Default |
| -------- | ------- | ------- |
| `ST_EXAMPLE_ACCOUNT` | The account the examples of sites, subscriptions, routes, transfers, transfer logs and transfer profiles use | `john` |
| `ST_SSH_PORT` | The SSH port of the partner in the SSH site examples, the connection test and the account setup | `8022` |

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
vi set_variables.local.sh
```

The files you create this way (`set_variables.local.sh`, `set_variables.local.bat`,
`config`, and the `settings.local.*` and `state.local.*` files of the features) are
listed in `.gitignore`: git does not track them, so they are never committed or
pushed, and your server address and password stay on your machine.

The scripts then pick your values up on their own. There is nothing to
configure inside the individual examples, and nothing to edit in the committed
`set_variables.local.example.sh`, `set_variables.bat` or `config.example` files.

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
held to it by `tests/offline/checks/check_python_risk.py`, the others by
`tests/offline/checks/check_risk_headers.py`):

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

The examples of a topic are numbered in the order to run them, one after the other:
`02` needs what `01` created or logged in to, so run `01` before `02`, and so on. The
last numbers of a topic usually delete again what the earlier ones created.

A feature (see [Features](Features/README.md)) is a whole scenario with its own helpers.
Its `00.run_all` script runs all the numbered scripts of the feature in order, and a
`99.cleanup_DELETE` script removes every object they created; `./00.run_all.sh --cleanup`
runs that clean-up at the end of the scenario. The topic folders of the Admin and EndUser
API have no `00` or `99` script.

If the configuration is missing, the scripts stop with a message telling you
which file to create rather than failing part way through a request.

## Where to find things

| Where | What is in it |
| ----- | ------------- |
| [Admin/API 2.0](Admin/API%202.0/README.md) | The **administrator API** examples (port 8444, or 444 on a root install: see [Which port?](#which-port)): `bash` and `bat` examples numbered by topic, `python` programs. Its README has the table of what is covered, the OpenAPI and the HTTP methods. |
| [EndUser/API 1.4](EndUser/API%201.4/README.md) | What the older **End User API 1.4** has and 2.0 has not: the **mailbox** (send a message to another user and read it), and what else is missing. Bash only. |
| [Admin/API 1.4](Admin/API%201.4/README.md) | What the older **API 1.4** has and 2.0 has not (path validation, the bulk resubmit of transfers), and where 2.0 has what looked missing. Bash only. |
| [Admin/API 2.0/python](Admin/API%202.0/python/README.md) | Small complete programs for real tasks: onboarding, bulk changes, configuration drift, certificate expiry. |
| [Admin/UseCases](Admin/UseCases/README.md) | Complete administrator scenarios, step by step, a learning path. |
| [EndUser/API 2.0](EndUser/API%202.0/README.md) | The **end user API** examples (bash, one for each call), and what is covered. |
| [EndUser/UseCases](EndUser/UseCases/README.md) | Complete end user scenarios, a learning path. |
| [Features](Features/README.md) | Complete solutions, one folder per feature, grouped by the release that introduced it. Each script checks the server version first and skips itself on a release that is too old. |
| [Features/Guidance](Features/Guidance/README.md) | Guides to **read**, not examples to run: time formats, reading the answers, sessions, Expression Language escaping, field names between releases. Each says who it is for and which release it was checked on. |
| [GLOSSARY.md](GLOSSARY.md) | The terms and acronyms. |
| [tests](tests/README.md) | The checks, and how to test your own scripts. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Working on the repository: its folders and files (`tools/`, `review/`, `.claude/`, `.github/`, `images/`, `tmp/`, `.gitignore`, `.gitattributes`), and the rules in `CLAUDE.md`. |
| `LICENSE` | The Apache License 2.0. |

## License and Support

These examples are published under the Apache License 2.0. See [LICENSE](LICENSE).

The included software is provided AS IS, with no implied or expressed warranty,
and is not covered by any Axway service level agreement. It is intended to
illustrate the API rather than to be run unmodified against a production
system. Take a backup before running anything that writes, and test the result
afterwards. Note in particular that several examples create, modify or delete
objects, and that `python3/stDeleteTestAccounts.py` deletes accounts in bulk.
