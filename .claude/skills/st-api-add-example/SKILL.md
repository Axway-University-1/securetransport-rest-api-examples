---
name: st-api-add-example
description: Add or change an example in the SecureTransport REST API 2.0 examples repository, following the established house style. Use this skill whenever someone wants to add a new example, port an existing one to another language, cover a new endpoint, contribute a script, or edit an existing example in this repository. Also trigger on "add an example for X", "write a bat version of Y", "cover the transfers endpoint", "contribute a python script", or when reviewing a change to these examples for consistency. Covers naming, the file header, configuration loading, bash and bat parity, and the python program skeleton.
---

# Adding an example

Read **st-api-gotchas** first if you are writing a new call. This skill is about
making the file look and behave like the ones already here.

## Before anything: where does it go?

| Kind of thing | Where |
| ------------- | ----- |
| One admin API call, demonstrated | `Admin/API 2.0/bash/NN.Topic/` **and** `Admin/API 2.0/bat/NN.Topic/` |
| One end-user API call | `EndUser/API 2.0/bash/NN.Topic/` |
| A complete job to run against an estate | `Admin/API 2.0/python/python3/` |
| A tool that reads an exported configuration XML | `Admin/API 2.0/python/utils/` |
| A complete solution for one product feature, added by a release | `Features/<feature-name>/`, `.sh` and `.bat` side by side. See `Features/README.md`. Every script starts with the `st_feature_check` version check. |

**bash and bat are kept at exact parity.** A new bash example without its bat
twin breaks that, and the README states the parity as a promise to Windows
users. Write both, with the same filename and the same behaviour.

## Naming

`NN.resource_METHOD.ext` — number by topic, then by HTTP method within the topic.

```
05.Accounts/02.accounts_POST.sh
05.Accounts/06.accounts_name_PATCH_with_file.sh
```

Rules learned the hard way:

- lower-case extension, always (`.sh`, not `.SH`)
- **no spaces** in file or folder names
- a dot after the number, then underscores inside the name
- the `Script Name:` line in the header must match the actual filename

A new topic folder uses the next free number. The existing gaps (10, 11) are
reserved for Transfer Profiles and Certificates.

## The file header

Every example opens with the same block. Keep the exact shape; the fields are
checked.

```bash
#!/bin/bash
# ==============================================================================
# Script Name: 02.accounts_POST.sh
# Author: <your name>
# Created: YYYY-MM-DD
# Location: <city>
# ==============================================================================
# Description:
# This script creates accounts using the `/accounts` endpoint.
# It demonstrates creating one account of each type:
# - user
# - service
# - template
#
# Usage:
# ./02.accounts_POST.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which is used to edit the retrieved JSON.
# - This script deletes data. Check the names before running it.
# ==============================================================================
```

In a `.bat` the same block uses `REM` instead of `#`.

The **Notes** section is where the value is. Put in it what the reader cannot
see from the code: prerequisites ("run 08.RouteTemplates first"), things the
script will destroy, required tools, and any API behaviour that will surprise
them.

## Loading the configuration

Always this, never a bare relative `source`:

```bash
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"
```

```bat
CALL ..\set_variables.bat
```

Then use `${ST_SERVER}`, `${ST_PORT}`, `${ST_USER}`, `${ST_PASSWORD}` — or
`%ST_SERVER%` and friends in a `.bat`. Never add a new configuration variable
without a matching entry in all four `.example` files.

In the EndUser tree, `set_variables.sh` also derives `${ST_URL}` and
`${ST_BASIC_AUTH}` for you. Use those rather than rebuilding them.

## The shape of a bash example

```bash
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts"

printf "Creating an Account of type User...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
  -H "accept: */*" -H "Content-Type: application/json" \
  -d "{\"name\":\"UserAccount\",\"type\":\"user\"}"
```

- quote `"${ST_USER}:${ST_PASSWORD}"`
- double-quote any payload that contains a variable, and escape the inner quotes
- `printf "...%s...\n" "${VAR}"` — never put a variable in the format string
- when only the outcome matters, print the code:
  `-s -o /dev/null -w "%{http_code}\n"`
- delete any temporary file the script created

## The shape of a bat example

Same content, plus:

- `^` for line continuation
- PowerShell where bash uses `jq`
- prefer `CALL :subroutine` over parenthesised blocks; if you do use a block,
  `SETLOCAL ENABLEDELAYEDEXPANSION` and `!VAR!`
- clean up with `IF EXIST file DEL file`

## The python skeleton

Copy an existing script rather than starting from scratch —
`python3/stReplaceSites.py` is the shortest complete one. Every script has:

1. The AS-IS disclaimer banner.
2. A version history line: `# V1.00 <name> <date> <what changed>`.
3. A header stating the APIs used, the usage line, and the outputs.
4. `stLogin()` and `stLogout()`, CSRF aware — copy them unchanged.
5. A `BEGIN / END Configuration Section` block containing the config file read.
6. `numAPIs = Value('i', 0)`, incremented per call, reported at the end.
7. `requests.Session()`, `verify=False`, and the warning suppressed.

The configuration read is identical in every script; copy it verbatim so that
one fix applies everywhere:

```python
stConfig = {}
configFile = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'config')
try:
    with open(configFile, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, value = line.split('=', 1)
            stConfig[key.strip()] = value.strip().strip('"')
except IOError:
    print('I cannot find the configuration file: ' + configFile)
    print('Copy config.example to config and set the values for your environment.')
    sys.exit(0)

stUrl = 'https://' + stServer + ':' + stPort + '/api/v2.0/'
basicAuth = base64.b64encode((stUser + ':' + stPassword).encode()).decode()
```

**If your script writes to more than one object, give it a `dryRun` flag and
default it to `True`.** The four bulk scripts do. It is what makes them safe to
hand to someone else.

## Before you call it done

- [ ] `bash -n` passes on every shell file you touched, matched case-insensitively
- [ ] python compiles: `python3 -m py_compile`
- [ ] the bat twin exists and behaves the same
- [ ] the `Script Name:` header matches the filename
- [ ] no server address, hostname, credential, customer name or internal IP
      anywhere in the file — placeholders are `<SERVER>` and
      `<BASE64_ENCODED_USERNAME_COLON_PASSWORD>`
- [ ] no JSON edited by text substitution
- [ ] temporary files removed by the script, and gitignored as a backstop
- [ ] a test covers the new or changed script (`tests/checks/`, see CLAUDE.md)
      and `./tests/run_all.sh` passes
- [ ] the README coverage table updated — the per-topic counts in it are meant
      to match a live count of the directories

A quick way to check that last point:

```bash
ls "Admin/API 2.0/bash/05.Accounts"/*.sh | wc -l
```

## Things that are deliberate, not accidental

- `Referer: THIS_IS_A_RANDOM_TEXT` — an arbitrary but consistent value. ST requires the
  header; see st-api-gotchas.
- `-k` / `verify=False` everywhere — these are lab examples. Say so rather than
  quietly dropping it.
- `python2` and its scripts were removed. Do not reintroduce that style; there
  is a python3 equivalent for every flow it covered.
