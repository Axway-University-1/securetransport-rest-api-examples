---
name: st-api-gotchas
description: The non-obvious traps in the SecureTransport REST API 2.0 and in scripting against it, collected from real debugging. Use this skill whenever writing, reviewing or debugging any call to the ST API, and whenever a call returns 401, 403, 422 or a silent partial success, whenever a PATCH is rejected, whenever a field does not change, or whenever a bash or bat script behaves differently from how it reads. Also trigger on questions about PATCH versus PUT, JSON Patch paths, adding or inserting route steps, CSRF tokens, the Referer header, paging, editing JSON in a shell script, jq, PowerShell ConvertFrom-Json, batch delayed expansion, or portability between macOS and Linux. Read this before writing a call, not after it fails.
---

# SecureTransport API and scripting gotchas

Each of these cost real debugging time. They are ordered by how likely they are
to bite you.

# Part 1: the API

## The Referer header is not optional

ST rejects API calls that arrive without a `Referer` header. The value does not
matter, but it must be **the same on every call in a session**, including login
and logout. The examples use `THIS_IS_A_RANDOM_TEXT`. If you get an unexplained 403 on a
call that looks correct, check the header.

That said, one lab server (5.5-20260827) accepted a call with no `Referer` at
all, over several separate integration runs and for both reads and writes.
Treat "no Referer means rejected" as the documented and safest assumption to
code against, not as something every server enforces - a script that omits the
header may still work on some servers and fail hard on others.

## /logs/transfers ignores accountName= - filter with account=

Confirmed directly, on 5.5-20260924: `GET /logs/transfers?accountName=X`
answers 200 with **every** account's transfers, whatever X is, even an account
that does not exist. No error, no warning: a count read that way is the whole
server's. The filter that works is `account=X`, an exact, case-insensitive
match, with `*` as a wildcard (`account=john*`).

This silently made the billable report, `16.TransferLogs` and
`stBillableTransfers.py` count the whole server until it was found. Do not
confuse it with the `accountName` field in the body of
`POST /transfers/operations?operation=pull`, which is correct there.
`tests/integration/checks/30.lookups_and_transfer_logs_read.py` checks that
`account=` really filters, and reports whether `accountName=` is ignored.

## Billing: "the first outbound of a file" means of a transfer chain

The Admin Guide's rule - every inbound is billable, the first outbound after
it is not, every later one is - is applied per transfer chain: the transfers
sharing one `coreId`. Confirmed directly by
`Features/audit-billable-transfers`, reading each transfer's `coreId`:

- A **Decompress** step keeps the archive's chain: two files unpacked from one
  archive and pushed out are two outbounds of one chain, so the second is
  billable. Pushed to two partners each, that is one free and three billable.
- A **Compress** step starts a new chain: the archive's one push is free.
- A **pull** out of a partner account shares the chain of the upload into it
  (its free first outbound); the pull landing in the receiving account starts
  a new chain, billable as an inbound.
- A file **deleted through the End User API** is logged as an outgoing
  transfer under its `coreId`, and is not billable.

**This was not theoretical - it was a real, confirmed gap, now fixed.** As of
this project's own history, 49 of the 52 `Admin/API 2.0/bash/*.sh` examples
(and the 40 `.bat` twins of the ones that have one) never sent a `Referer`
header at all - only `01.myself_cookie_POST.sh`,
`02.Introduction/06.myself_DELETE.sh` and `90...Acknowledgment.sh` did
(confirmed directly by grepping the tree, not by memory). They worked against
a lenient lab server, which is exactly why nobody building or running them
noticed - point them at a server that enforces the documented contract and
they would have failed. All 89 files were fixed the same mechanical way:
a `REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"` variable (`set
REFERER_HEADER=...` in `.bat`) defined right after sourcing
`set_variables.sh`/`.bat`, and `-H "${REFERER_HEADER}"` (`-H
"%REFERER_HEADER%"` in `.bat`) appended after every existing `accept:` header
- confirmed, before touching anything, that every single curl invocation in
every affected file already had an `accept:` header to anchor on, so the
fix is a precise append next to a known, unique substring, never a blind
`sed`-style pattern match. The bundled integration mock (see
`tests/integration/`) enforces `Referer` on every call, matching the
documented behaviour rather than this one lab's leniency, so this fix is
what makes the bash checks agree between `--mock` and a real, less lenient
server rather than only passing against this one lab's leniency.

## CSRF tokens, from the 20230525 release onwards

`Webservices.Admin.CsrfToken.enabled` defaults to `true` from that release. When
it is on:

1. `POST /myself` returns a `csrfToken` **response header**.
2. Every later call in the session must send it back as a `csrfToken` header.

The python examples do this. Any script written before that release will fail
against a current server until it is updated. This is the single most common
reason an old script stops working.

**Confirmed directly against a real, CSRF-enabled server: this only applies to
session-cookie authentication.** A bare call carrying a fresh `Authorization:
Basic` header - no cookie, no csrfToken - succeeds on its own, including for
writes. This is why almost every bash example works without ever handling
CSRF: none of them log in and keep a session, they pass `-u user:pass` on
every single curl call, and that turns out to be exempt from the CSRF check
entirely. It makes sense once you consider what CSRF protects against - a
browser silently attaching a cookie to a request the user did not intend.
That risk does not exist when the credential is put on the request explicitly
and afresh every time.

Exactly two bash examples are the exception, because they are the only two
that actually keep a session: `01.Authentication/01.myself_cookie_POST.sh`
and `02.Introduction/06.myself_DELETE.sh` (and their `.bat` twins) log in once
with a cookie jar and reuse it. Both were found, the same way the missing
`Referer` header was, to never send a `csrfToken` back on the later calls in
that same session - a real, confirmed bug, silently masked by this project's
own lab server, which was confirmed directly to accept a cookie-based GET
with no `csrfToken` at all (200, not 403) even with CSRF enforcement
notionally on. The bundled integration mock enforces the documented contract
strictly and caught this immediately with a 403 `"invalid csrfToken"` once
the (separately real) missing-`Referer` bug was fixed and stopped masking it.
Fixed the same way the python examples already did it: capture the
`csrfToken` response header from the login call (`curl -D headerfile`, then
read it back out), and send that same value back as a `csrfToken` header on
every later call in the script - captured once, never rotated, matching
`stUpdateAllRoutes.py`'s own pattern.

## PATCH cannot insert into the middle of an array

You can `replace` an element by index, and `add` at a position or at the end with
`-`, but rebuilding an array in place is unreliable. **To insert a step into an
existing route's steps array, read the whole route, change your copy, and PUT it
back.** `python3/stUpdateRouteWithPut.py` is the worked example.

PUT replaces the entire object. Always send back the object you read with your
change applied — never a hand-built fragment, or you will silently drop fields.

## replace needs the field to exist; add creates it

This is the usual cause of a **422** from a PATCH:

- `replace` on a field that is not set yet fails.
- `add` on a field that is already set may fail or duplicate.

When you do not know whether a field is set, GET the object first.
`python3/stUpdateAllSubscriptions.py` shows a body that mixes both operations.

## A route step has no id — it is addressed by index

There is no step identifier. A step is referenced by its position:

```
/steps/1/customProperties/mHostName
```

So you must GET the route, find the index of the step you want, and build the
path from it. Never assume an index. `python3/stUpdateAllRoutes.py` does this
properly.

## Appending to an array uses a dash

To add to the end of a list without knowing its length:

```json
[{ "op": "add", "path": "/businessUnits/-", "value": "HumanResources" }]
```

A numeric index is only valid up to the array's current length - confirmed
directly: `add` at `/addressBookSettings/contacts/1` on an account whose
`contacts` array is still empty 400s with `"Array index 1 out of bounds"`,
even though the same call succeeds once index 0 is already occupied. This was
a real bug in the shipped `05.Accounts/06.accounts_name_PATCH.sh`: it hardcoded
index `1`, which only ever worked because the real account it was tested
against already had one contact. Fixed to use `-` instead, which works
whether the array is empty or not.

## remove nulls a field; it does not drop it from the response

`{"op": "remove", "path": "/addressBookSettings/nonAddressBookCollaborationAllowed"}`
returns 204, but the field is still present in the object afterward, with a
`null` value - confirmed directly, on both a field that had a value set and
one that never did. For a field the schema always carries, do not assert the
key is absent after a remove; assert its value is `null`.

## Setting addressBookSettings.policy to "custom" needs two sources first

Confirmed directly: `{"op":"replace","path":"/addressBookSettings/policy","value":"custom"}`
400s with `"addressBookSettings.sources must be at least two."` on an account
whose `sources` array has fewer than two entries. An LDAP-integrated account
normally has two by default (LDAP and Local, per the comment in
`06.accounts_name_PATCH.sh`); a plain account created fresh through the API
does not. The shipped script never checks this call's response code, so the
failure is silent rather than a shell-level error.

## Paging: ask for a page size and compare the return count

List calls return at most `Webservices.EntriesPerPage` objects, 100 by default.
The pattern used throughout:

```
GET /collection?offset=0&limit=200
```

then keep going while `resultSet.returnCount` equals your limit, and stop when it
is smaller. Every python example that walks a collection does this.

## A new object's id comes back in the Location header

POST does not return the created object. The URL of the new resource is in the
`Location` response header, and the id is its last path segment. Use `curl -D` to
capture the headers. `bash/09.CompositeRoutes/02.routes_POST.sh` does this.

## Expected status codes

| Call | Success |
| ---- | ------- |
| POST that creates | 201, with a `Location` header |
| PATCH | 204, no body |
| PUT | 204, no body |
| DELETE | 204 |
| GET, HEAD | 200 |

Checking for 200 on a PATCH will report failure on success. Use
`-o /dev/null -w "%{http_code}"` to read just the code.

## POST /myself is a login call, not "get info about myself"

Confirmed directly: `POST /myself` (with Basic auth) returns only
`{"message": "Logged in"}` - it does not return the account object the way
`GET /myself` does. This is easy to assume otherwise from the name alone;
`02.Introduction/05.myself_POST.sh` demonstrates the login call specifically,
not a way to read your own account data. Use `GET /myself` for that.

## Administrators are not accounts, and default to localAuthentication=false

`/accounts` and `/administrators` are two different resources - confirmed
directly: `POST /accounts` with `"type":"administrator"` is rejected with
`"Invalid discriminator value"`. Administrators live under their own
`/administrators` endpoint, with a `roleName` (e.g. `"Master Administrator"`)
instead of the `type=user/service/template` model accounts use.

An administrator created through `POST /administrators` defaults to
`localAuthentication: false`. Basic-auth login against it then fails with a
plain 401, with no indication in the error why - confirmed directly. Set
`"localAuthentication": true` explicitly in the creation body for
password-based login to work at all.

## loginRestrictionPolicies is a real, separate resource, and starts empty

Confirmed directly: `POST /loginRestrictionPolicies` requires a `type`
(`ALLOW_THEN_DENY` or `DENY_THEN_ALLOW`) and creates a policy with an empty
`rules` array, `isDefault: false` and `businessUnits: []` - not attached to
anything, so it has no effect on any real login until something is
explicitly configured to use it. Safe to create and delete freely for
testing `stAddLoginRestrictionRule.py`, which takes the policy name as a
real command line argument rather than hardcoding one.

Confirmed directly, later, adding the Admin examples from the reference
(`26.LoginRestrictionPolicies`): `name=` takes the `*` wildcard and ignores case, and
`isDefault=` works, unlike most other resources. `fields=` must ask for
`businessUnit` (singular) to get the field `businessUnits`; `businessUnits` answers 400. A rule
is **known by its name**: adding a rule whose name exists replaces it, a PUT keeps the rules'
ids, and `/rules/-` puts the new rule **first**, not last. The address is checked
("Unknown format for client address"), the type is checked, an Expression Language condition
is **not** (`${nonsense(` is accepted). A business unit is assigned with
`add /businessUnits/-` (idempotent; a unit that does not exist is 400) and taken away by
its position. A PUT with another `name` renames the policy; a PUT with no rules and no business
units empties both. `businessUnits?assignedToLoginRestrictionPolicies=`, the filter the
server links to, filters nothing. **Enforcement was not observed**: on the lab a policy denying
`*`, assigned to a business unit, did not stop that unit's accounts logging in over FTP or the
EndUser API, immediately or two minutes later, with either type. Do not make a policy the
default to try it: that applies it to every account that has none.
`tests/integration/checks/46.login_restriction_enforcement.py` asserts the refusal (and that an
account outside the unit still gets in) and fails on that lab until enforcement works.

## A certificate's caPassword is one real secret, shared by generation, import and nothing else

Confirmed directly: `POST /certificates` rejects any `caPassword` that is
not the one this specific server's certificate authority was actually
configured with, with `"Specify a valid CA Password."` - not a complexity
rule, and there is no way to manufacture a valid one without already
knowing it. `stImportKey`'s hardcoded `"Axway123"` (in
`stBuildFullTestAccount.py`) is a placeholder for whatever the original
author's own lab used, not a value that works elsewhere.

Once you have the real value, it gates two genuinely different things,
confirmed directly:

- **Generating** a brand new certificate through a plain JSON
  `POST /certificates` (no multipart, no external key file at all -
  `type`, `usage`, `subject`, `keySize`, `validityPeriod`, `account`, and
  `caPassword`) is a completely different code path from *importing* an
  externally created one. `26.python_get_private_cert.py` uses exactly this
  to create a real private certificate for `stGetPrivateCert.py` to export -
  the first time this project had one to test against at all.
- **Importing** an external key via multipart (`stImportKey`'s own
  mechanism) needs the same `caPassword`, *and* the key file's own
  passphrase must match the `"password"` field sent alongside it -
  confirmed directly: a key generated with `ssh-keygen -N ""` (no
  passphrase) got `"Failed to decrypt SSH Private key. Wrong password."`
  even with the correct `caPassword`; regenerating it with `-N 12345678` to
  match the script's own hardcoded `"password": "12345678"` field then
  succeeded. `28.python_build_full_test_account.py` does exactly this with
  a real, disposable, freshly generated key.

Separately confirmed while chasing an unrelated 403 down: the `password`
query parameter `stGetPrivateCert.py` sends on the *export* call
(hardcoded `12345678`) is not validated against anything at all - it is the
passphrase the exported file gets encrypted with, freely chosen by the
caller. Only the two `caPassword` uses above are gated by the real secret.

## stBuildFullTestAccount.py hardcoded the wrong account name in two places

Confirmed directly, a real bug: `stImportKey` and `stGetKeyId` both
hardcoded the literal string `"TestAccount1"` instead of using the
script's own configured `accName` variable, which every other function in
the file (`stCreateSiteFolder`, `stCreateSiteSFTP`, `stCreateSubscription`,
`stCreatePackageRoute`) already does correctly. Fixed to use `accName` in
both places. The failure mode this produced is worth knowing on its own:
importing a certificate against an account name that does not exist got a
403, not a 404 - nothing to do with CSRF or permissions, confirmed by
reproducing the exact same request against a real, existing account, which
succeeded immediately.

Also confirmed while tracking that down: a GET call inside a kept session
does not need a `csrfToken` the way a POST/PATCH/PUT/DELETE does -
`stGetKeyId()` and `stGetTemplateRouteId()` never send one, and that is
fine. CSRF here gates writes, not reads - the existing "CSRF tokens" entry
above was never wrong about POST/PATCH/DELETE, this just confirms GET was
never in scope either.

## Client certificate auth needs a server-wide policy flag, off by default

`stUpdateAllAccounts.py` authenticates with a TLS client certificate
(`session.cert = ...`, no `Authorization` header at all) rather than Basic
Auth. Confirmed directly: presenting a client certificate whose subject
matches an administrator's own `certificateDN` field still gets a plain 401
"Authentication required" unless `Admin.ClientCertificateAuthentication` (a
system configuration option, values `none`/`optional`/`required`) is set to
something other than its default of `none`. The TLS handshake itself accepts
an optional client cert either way - the rejection happens at the
application layer, not the TLS layer, which makes it easy to mistake for a
DN-mapping problem when it is actually this policy flag.

This is not a per-account or per-request setting - it is server-wide, and it
changes what every administrator's authentication is evaluated against.
Treat enabling it the same as any other change to shared authentication
policy - it needs an explicit decision, not something to flip to get one
script's test running.

Getting far enough to confirm even that much hit a second, separate wall,
worth recording since it is not about the API at all: this session's own
tooling classifies both creating an administrator with an elevated role
and reading the existing `/administrators` collection as a privilege-grant
risk, and refused both outright - even the bare `GET`, with nothing to
create at all. Per how that classifier is meant to work, the response here
was to stop and hand the decision back rather than retry through a
different tool, a smaller request, or anything else that reaches the same
place. `stUpdateAllAccounts.py` accordingly stays untested for two
independent reasons now: the server-wide auth policy below, and this.

One correction to an earlier note here: the option comes back
`"readOnly": true` from `GET /configurations/options/...`, and this was
first recorded as the API itself refusing a `PATCH` to it. That was wrong -
confirmed directly, in a separate and unrelated case:
`StatisticsSummaryReport.ClientId`, which also reports `readOnly: true`,
accepted and kept a real `PATCH` without complaint. `readOnly` describes
whether the admin UI lets you edit the value, not whether the API does - the
two are independent. What actually stopped the `Admin.ClientCertificateAuthentication`
change was this session's own tooling declining to attempt that one specific
call, because it is an authentication policy rather than a data value - a
client-side judgement call, not a server response that was ever observed.

## /daemons/{name} only ever accepts "ssh"

Confirmed directly, on a server with five protocol daemons (`ftp`, `http`,
`pesit`, `ssh`, `as2`): `GET`, `PUT` and `PATCH` on `/daemons/{name}` reject
every value except `"ssh"` with a 400
(`"Invalid value for parameter name, expected (ssh)"`), regardless of which
of the others exist or are running. This is not one hardcoded example among
several equally valid choices, the way an account or application name is -
`03.daemons_name_PUT.sh` and `04.daemons_name_PATCH.sh` hardcode `NAME="ssh"`
because that is the only name this endpoint will ever address. There is no
"test daemon" to redirect either script at.

## Fields that are specific to one account type need the type

Asking for a type-specific field without saying which type returns nothing:

```
GET /accounts/UserAccount?fields=addressBookSettings           # empty
GET /accounts/UserAccount?type=user&fields=addressBookSettings # works
```

The `type` is always returned whether you ask for it or not.

## HEAD is the cheap existence check

`--head` (or `-I`) returns headers only. 200 means the object exists, 404 means
it does not. Used before every delete in the examples.

## Field names drift between releases

Names have changed across versions. Before relying on a field, confirm it in the
Open API page for **your** version at
`https://<SERVER>:8444/api/v2.0/docs/index.html`.
`python3/stCertificateExpiry.py` shows the defensive approach: try several likely
names, report which one was found, and print the available fields if none match.

One field confirmed this way: on `GET /myself` (a 5.5-20260827 server), the
current administrator's login name is the top-level `loginName` field - not
`name`, and not nested under a `user` or `administrator` object the way an
account's own record is. `tests/integration/checks/01.connect.py` does not
hardcode this; it searches the whole response and reports where the value was
found, which is the safer pattern until a field has actually been confirmed
against the version you are targeting.

## Duplicate names are rejected

Route template names, server names and account names must be unique. A bulk
create loop over a list with repeats will fail on the repeats — worth
de-duplicating the list first.

## Some object types allow only one instance per server, regardless of name

Confirmed directly: a server rejected a second application of type
`AccountFilePurge` with `"Only one instance of this type is allowed."`, even
under a different name than the one that already existed. This applies to
every entry in `04.Applications`'s `MAINTENANCE_APPLICATIONS` list - only one
`AccountFilePurge`, one `AuditLogMaint`, one `TransferLogMaint`, and so on, can
exist at a time. Check by **type** before creating one, the same way
`02.applications_POST.sh` already checks the flow type before creating that -
checking only by name is not enough, since a differently named instance of the
same type still gets rejected.

Different maintenance types also have genuinely different schemas - this is
not just a naming collision to work around by picking another name of the
same type. Confirmed directly: an `AccountTTL` application rejects the exact
body `AccountFilePurge` accepts, with a 400 `"Unsupported parameter -
deleteFilesDays"`; `ArchiveMaint` accepts an almost-empty body
(`{"type": "ArchiveMaint", "name": "..."}`) that `AccountFilePurge` would
reject for missing required fields. Do not assume one maintenance type's
request body is a safe stand-in for another's.

## The EndUser API: one thing not covered by any shipped example, one now fixed

- **Deleting an account does not delete its home folder's files from disk.**
  Confirmed directly: an account was deleted, a new one created with the same
  `homeFolder`, and the files an earlier test had uploaded were still there,
  attached to the new account. A "freshly created" account is not guaranteed
  to have an empty home folder if the path was used before.
- **`DELETE /files/{path}` works** - confirmed directly, 204, and the file is
  gone from the listing immediately. `EndUser/API 2.0/bash/02.Files/07.files_filepath_DELETE.sh`
  now demonstrates it (no `.bat` twin - the EndUser tree has no `bat/` folder
  at all, unlike Admin).

## The EndUser API, against its own reference

Confirmed directly on 5.5-20260924, while adding an example for every
resource of the EndUser API reference (`tests/integration/checks/33.enduser_api_scripts.py`):

- **No csrfToken is needed.** The login answers with one, but a POST, PUT,
  PATCH or DELETE without it succeeds. The session cookie is enough.
- **Changing the password ends the session.** The next call with the same
  cookie answers 401: log in again with the new password.
- **Lists are plain arrays** for `/transfers`, `/myself/addressBook` and
  `/secretQuestions` - not the Admin API's `{resultSet, result}` envelope.
- **An address book id holds a `:`**; URL-encode it in `/myself/addressBook/{id}`.
- **A folder can only be shared with a user the server knows**: an unknown
  email answers 400 "Unable to share folder ... with user ...". The admin API
  does not take `sharingAllowed` on an account, though the end user's
  `GET /myself` shows it.
- **A wrong `Content-MD5`** answers a bare 500, "Error while uploading file",
  and File Tracking logs a Failed upload. A right one answers 201.
- **A file operation's status is the operation's, not the file's.** MD5Calc
  answers IN_PROGRESS, then DONE with a base64 checksum. An Upload stays
  IN_PROGRESS after its last chunk, though the file is whole. A cancelled
  operation answers 404 afterwards.
- **The content of an Upload** goes in with PUT as octet-stream (in chunks with
  `Content-Range`, if wanted), or with POST as a multipart form. POST as
  octet-stream answers 415.
- **A folder monitor run needs no transfer site**: it moves the files between
  two folders of the user's home, logged as Incoming, protocol `folder`.
- **A pull summary for an unknown operationIndex** answers 200 with every
  count 0, not 404.
- **`/serverTime`** writes the offset as `+0300`, not the `Z` the reference shows.
- **The secret question service** answers 503,
  `error.secretQuestion.serviceDisabled`, when it is not enabled.

## The Admin API, against its own reference

Confirmed directly on 5.5-20260924, while adding examples resource by resource
from the Admin API reference (`tests/integration/checks/34` onwards):

- **The `metadata.links` the server builds are wrong for a name with a space.**
  It encodes the space as `+` and then the `+` as `%2B`:
  `/administrators?roleName=Master%2BAdministrator` and
  `/accounts?businessUnit=example%2Bbu` find nothing. Build the search
  yourself, with the name URL-encoded once (`curl -G --data-urlencode`).
- **`/accessPolicies` answers a plain array**, and a rule's id is its line in
  pg_hba.conf: the ids after a deleted rule move up. List again before each
  delete, never delete several ids from one listing.
- **`/accountSetup` is not all or nothing.** A body that fails part of the way
  leaves what came before created. Every site and profile in it needs
  `account`. An account that exists is skipped, not refused.
- **`/addressBook/sources` has no POST or DELETE**; PUT and PATCH answer 204.
- **`POST /administrators` needs `parent`**, the administrator it is created
  under, though the reference does not mark it required: 400 "Please specify
  parent administrator" without it.
- **Administrator API keys** (`/administrators/{name}/api-keys`): the key is in
  the POST answer only; at most 2 per administrator (409); `validityDays` or
  `expiresAt`, not both (400). The `SECURETRANSPORT-API-KEY` header alone
  authenticates. A method the key's permissions do not cover answers a
  plain-text 403; a revoked key a plain-text 401, "Authentication required."
- **A role's menus come back in no fixed order.** `add` to `/menus/-` adds
  the menu, not necessarily at the end. `DELETE /administrativeRoles/{name}?targetRoleName=`
  moves the role's administrators to that role.
- **Business units:** `baseFolder=` as a filter is ignored (every value gives
  every unit). `parent` reads null even for a nested unit; the nesting shows in
  `businessUnitHierarchy` and `metadata.links.parentBusinessUnit`, and
  `parent=` as a filter works. A delete is refused, 400, while the unit has
  nested units or accounts.
- **Certificates:** `expirationTime.from` and `.to` are in milliseconds, not
  the Unix seconds the reference implies; in seconds they find nothing. A
  generate (JSON body) answers 201 as multipart/mixed, the JSON in the first
  part, the id in `Location`; an import (multipart/mixed body) answers 200 with
  plain JSON. PATCH works only on `accessLevel`, `additionalAttributes` and
  the external store fields. `POST /certificates/{id}/operations?operation=export`
  needs a multipart form body even for pem and crt (`-F exportPassword=`),
  otherwise 400 "Entity is empty."; `includePath=true` on a GET answers an
  array, the certificate then its chain. Deleting an account deletes its
  certificates.
- **Certificate signing requests:** the CSR itself is only in the POST
  answer (multipart/mixed); a GET answers the JSON alone, and 406 to any other
  Accept. Read back, `keySize` is 0 and `signAlgorithm` null. With a filter,
  `totalCount` still counts every request. Completing (multipart form, `alias`
  and `certificateFile`) answers 200, creates the certificate and removes the
  request; a CA the server does not trust is accepted, "Not chained to a
  trusted root".
- **Configurations are options underneath.** Sentinel, external stores and S3
  storage profiles are stored as Server Configuration Options
  (`AxwaySentinel.*`, `TM.ExternalStores.<name>`,
  `StorageProfiles.S3.Registry.<name>.*`), and the options endpoint can do what
  the dedicated one refuses. Once a Sentinel `host` is set, `/configurations/sentinel`
  refuses an empty one ("host must not be null or empty") and then any change:
  turn reporting off, then clear `AxwaySentinel.RemoteHost.host` and
  `AxwaySentinel.OverflowFile.path` and restore `.RemoteHost.port` and
  `.Heartbeat.delay` through `PUT /configurations/options`. An option is cleared
  with `[""]`; `[]` answers 400 "Invalid argument length.".
- **External stores:** `GET /configurations/externalStores?name=` with a pattern
  ending in `*` answers 404 "External Stores configuration is not valid" once it
  matches a store - it also matches the store's companion option
  `TM.ExternalStores.<name>.encryptedFields`. Use an exact name. `fields=` is
  ignored. The `test` operation answers 200 whatever happens; read
  `fetchStatus`, `connectionStatus`, `authenticationStatus`.
- **S3 storage profiles** have no resource: add the name to
  `StorageProfiles.S3.Registry` (one value each), set
  `StorageProfiles.S3.Registry.<name>.Bucket`, `.Region`, `.CustomEndpointUrl`,
  `.AccessKey`, `.SecretKey`. Saving them tests the connection (400 when the
  bucket cannot be reached); `test` is a HEAD on the bucket.
- **Other configuration endpoints:** a logging option's XML comes only with
  `Accept: application/xml` (204 when none is set); a PUT on one that was never
  set answers 400 "not eligible for propagation". Enabling Sentinel needs
  `overflowFilePath`. The database `test` operation is a multipart form and
  needs host, port, databaseName, username and password. Login settings are
  validated whole on every change, so already inconsistent settings refuse even
  a no-op. Some option groups the list returns answer 501 when read.
  `allowedSTServers` answers 404 on a standalone server.

- **Denied users** (`/deniedUsers`): only GET, POST and DELETE; GET or HEAD on one
  name answers 405. POST answers 201 with the entry's address in `Location` and
  no body. `ttl` is in hours and left out for a permanent block (`blockedUntil`
  null). **POST accepts an empty `loginName`, and the entry can then not be
  removed through the API** (DELETE with an empty name is 405, with a space or
  a NUL it is "not found"); also 0, negative and absurd `ttl` values, which
  give entries that have already expired. Check both before sending. A
  duplicate is 400; DELETE of a name not in the list is 400, not 404. An
  expired temporary entry stays listed until the server's blocked-users cleaner
  removes it. The `loginName` filter ignores case but entries are case
  sensitive: `example_denied` and `EXAMPLE_DENIED` coexist, and DELETE takes the
  exact name. The date filters take yyyy-MM-dd, RFC 2822 or a millisecond
  timestamp. A blocked name is refused at the EndUser login (`POST /myself`)
  with 401 "Login failed. Re-submit your credentials." - the same text as a
  wrong password, so test with a login that worked just before - and logs in
  again as soon as the entry is removed; other accounts are unaffected.

- **Events** (`/events`) are the tasks being processed now, so the list is usually
  empty. Confirmed directly: a file uploaded to an Advanced Routing subscription
  first shows a short-lived `DEFAULT` event for the arrival, then an
  `ADVANCED_ROUTING` one that is `ready` (queued) and becomes `active`. A send
  step towards a partner that accepts the connection and never answers (a
  TcpSink) keeps it active; to make events for a test, use that. An event can stay
  `active` after its transfer has `Failed`; `POST /events/operations?operation=delete`
  with `{"ids": [...]}` removes it, answering 200 with `deleted` or `not found` per
  id. Any other `operation` answers 200 with `{}` and does nothing. `status` is
  matched exactly (`active`, not `ACTIVE`); an unknown `processorType` finds
  nothing rather than a 400; `arrivalTime`, `lastHeartbeatAfter` and
  `lastHeartbeatBefore` are milliseconds, a date answers 400 "For input string".
  An unknown id is 404. A file that already exists in the folder is not a new
  arrival, and deleting an account leaves its home folder on disk: give a test
  upload a name of its own and delete it afterwards.

- **ICAP servers** (`/icapServers`) scan a transfer only for the **business units that
  list them in `enabledIcapServers`**, and only while `serverEnabled` is true; an
  enabled server that no unit lists scans nothing, so a test can scope the scan to a
  throwaway unit and leave every other transfer alone. Confirmed directly: ST sends
  `OPTIONS`, then each file as a `REQMOD` with a preview (`X-Authenticated-User` is
  `Local://<account>` in base64); a block (ICAP 200 with an HTTP 403) leaves the
  transfer `Failed` and removes the file, after the file has first been listed (the scan
  is asynchronous, a few seconds); several files may be scanned in any order. With the
  server unreachable, `denyOnConnectionError` true refuses the file and false lets it
  through; disabled, nothing is scanned. A PUT whose body has another
  `basicSettings.name`, or a PATCH of `/basicSettings/name`, **renames** the server.
  The `basicSettings.name`, `.url` and the other filters are exact (no `*`, case
  sensitive); the `url` is not checked (`http://x` is accepted); maxSize and
  previewSize are required. Deleting a server a unit still lists succeeds and takes it
  out of that unit's list. `businessUnits?icapServer=` filters nothing (every value
  lists every unit): read `enabledIcapServers` and select yourself. In a business
  unit an account's home folder must end with the account name, so a fresh folder per
  test run has to come from the unit's `baseFolder`.

- **LDAP domains** (`/ldapDomains`): `bindDn` and `bindDnPassword` are required, though
  only `name` is marked. The server **resolves the host when it saves a domain**: a
  name it cannot resolve answers 400 "Invalid server host", an address always works.
  The bind password reads back encrypted (`{AES128}...`); sending that text back in a
  PUT keeps the password, plain text is encrypted anew, and a body with no password is
  400. The defaults are not the reference's: `referralsAllowed` and
  `anonymousBindsAllowed` read true. The `Location` of a POST ends with the domain's
  **id**, but the path takes the **name**. A PUT with another `name`, or a PATCH of
  `/name`, renames it. `name=` and `bindDn=` are exact (no `*`, case sensitive);
  `isDefault=` as a filter fails with "unable to comply" for true and false. A PATCH
  can set `/isDefault` to true but cannot set it back (400 "You cannot set precedence
  on non default domain"); an added server (`/ldapServers/-`) takes order 1. The
  `testConnection` operation answers 200 whether or not it worked, reads the message
  (`Successful Connection.` or `Connection failed.`), and only opens a TCP connection:
  it sends nothing, so a TcpSink is enough to play the directory. A domain is used for
  logins only when the server's login settings turn LDAP on, a server-wide change.

## The EndUser port does not reliably follow the admin-port-minus-one convention

This project documents 8444/8443 for a non root install and 444/443 for a root
one. Confirmed on one real server: the admin API answered on 444 (root style)
but the EndUser API was not on 443 at all - it answered on 8443 instead, a
mixed configuration that matches neither documented pair cleanly. Try the
documented pairing first, but confirm the end user port rather than assume it,
particularly against a server you did not configure yourself.

## Expression Language: which fields carry it, and how it is escaped

See `Admin/API 2.0/bash/14.ExpressionLanguage/` and its python3 twin for
worked, server-verified examples of everything below.

- **A route's own condition can be EL, not just a step's.** Confirmed
  directly: `conditionType` accepts `MATCH_ALL`, `MATCH_FIRST`, `ALWAYS` or
  `EL`. When it is `EL`, the expression text goes in a field simply named
  `condition` - the same field name whether it is the whole route or one of
  its steps.
- **A route step's `fileFilterExpression` is not EL.** It is a plain
  glob/regex string evaluated by the file filter, not the EL engine, keyed
  by `fileFilterExpressionType` - confirmed to accept exactly `GLOB`,
  `REGEXP` or `TEXT_FILES` (not "REGEX").
- **A transfer site's equivalent field uses different names and case.**
  `downloadPatternType` accepts lower case `glob` or `regex` - not `REGEX`,
  `REGEXP`, or upper case at all. Two fields for the same idea
  (`fileFilterExpressionType` on a route step, `downloadPatternType` on a
  site), two case conventions, two spellings for the regex option - each
  confirmed directly, since guessing either from the other was wrong both
  times.
- **Two independent backslash-doubling rules can stack.** A literal
  backslash in *any* hand-written JSON string value must be written as `\\`
  in the JSON text, or the JSON is invalid - confirmed directly, a single
  `\.` in a curl `-d` body gets `"Incorrect JSON format"` back immediately,
  before the regex is ever evaluated. This applies regardless of whether the
  value is EL. When the value *is* an EL string literal that separately
  needs its own backslash doubled (the EL documentation's own rule, for a
  regex passed to `.matches()`/`.replace()`), the two requirements compound:
  a semantically single backslash needs to appear as **four** backslash
  characters in the JSON source text of a hand-written curl body - two for
  the EL layer, doubled again for JSON. Confirmed directly by creating a
  route with each form and reading back exactly how many backslash
  characters were stored in each case. This composition is specific to
  languages (bash, or anything building JSON as literal text) with no
  automatic encoder - a JSON library like Python's `json.dumps`
  (`requests`' `json=` parameter uses it) only ever needs the EL-level
  doubling, since it handles the JSON layer's own escaping for you.
- **`customProperties` belongs to a transfer request, not a site.** The
  `${DXAGENT_TRANSFERSAPI_*}` pattern lets a site's own field (`host`,
  `downloadPattern`, ...) hold a template that is resolved later - but
  confirmed directly, sending a top level `customProperties` object in a
  site's own `POST`/`PUT` body is rejected as `"Unsupported parameter"`. The
  site just stores the literal template string verbatim; `customProperties`
  is supplied per request on the actual transfer operation, which is a
  different call this project does not yet have an example for.

## The Transaction Manager has no start operation - only stop

Confirmed directly, while a real server's Transaction Manager was still
running (nothing was ever put at risk to find this out):
`POST /transactionManager/operations?operation=start` is rejected outright -
`"stopGracefully.arg1 must match \"(?i)(stop)\""`. Unlike daemons, servers
and cluster services (all of which accept both `start` and `stop` on their
own `/operations` endpoints), this endpoint only ever implements stopping
the TM. There is no confirmed way to bring it back up through this API at
all. Any script or check that stops the TM has no way back - which is why
`tests/integration/checks/manual.graceful_scripts.py` runs a copy of
`stGraceful.py` with its TM-stop call removed entirely, rather than
round-tripping it the way every other operation in that check is
round-tripped.

## AS2's listener can be disabled independently of its running/stopped state

Confirmed directly: a server's AS2 daemon can accept
`POST /daemons/operations?operation=start&daemon=as2` with a 200, yet the
response body itself reports `isSuccessful: false` and
`"Can not start AS2 daemon - the default server As2 Default is not
enabled."`. This is a separate, more persistent setting - the server's own
AS2 listener configuration - from the daemon's ordinary running/stopped
toggle that `start`/`stop` otherwise flips. Do not assume a successful
(200) response to a daemon `start` operation means the daemon is actually
now serving traffic; check the response body's `isSuccessful` field and, if
false, read the message rather than trusting the status code alone.

## Starting a server right after its daemon can transiently fail even though the daemon is (or will be) up

Confirmed directly, recovering from the incident described below: issuing
`POST /servers/operations?serverName=X&operation=start` immediately after
starting `X`'s underlying protocol daemon can come back with
`"the X daemon is not started"` or `"the port is in use"`, even though the
daemon reports (or is about to report) `Running`. This is a real timing
race on the server side, not a stable error - a fresh `GET` moments later,
or a retried `start` call, succeeds without anything else changing. Any
script that starts a daemon and then immediately starts its server should
poll the daemon status until `Running` first, and retry the server start a
handful of times, rather than trusting a single attempt's response either
way.

## A retry loop needs to tolerate the admin API being briefly unreachable, not just a status that has not changed yet

Confirmed directly, in `23.connect_operations_scripts.py`: while daemons and
servers are being stopped and restarted, a single `GET` from the
verification client can fail at the connection level (a bare
`http.client`/`urllib` exception, surfaced here as `st_client.STError`) -
not a slow or wrong answer, no answer at all. A `wait_until(predicate,
...)` retry loop that calls the predicate directly, with no `try`/`except`
around it, dies on the very first attempt that lands during that window,
even though every attempt after it would have succeeded - confirmed by
re-running the same check moments later with nothing else different and
getting a clean pass. Any retry loop polling this API through a real
daemon/server restart needs to catch a transient connection error the same
way it treats "not true yet" - one bad attempt should not end the retry
loop early.

The window has more than one shape. Confirmed directly, later in the same
check: the server can also accept the connection and then not answer, and
`urllib` raises that as a plain `TimeoutError` (an `OSError`), not as
`URLError` - so a client that only wraps `URLError` lets it escape a loop
written to survive exactly this. `st_client.py` now turns any `OSError` from a
request into `STError`. And the final "is everything back as it was?"
comparison needs the same patience: the servers come back asynchronously
after the last request, so wait for the state to match, then compare.

## A graceful stop with a timeout keeps running server-side after the client that issued it is gone

This is the most safety-critical finding of this whole project, from a real
incident during development - see
`tests/integration/checks/manual.graceful_scripts.py`'s own docstring for
the full account. Short version: `stopDaemon`-style operations that take
`graceful=true` and a `timeout` in seconds appear to keep executing on the
server's own clock, **independent of the client that triggered them** -
killing the calling process (a subprocess timeout, a dropped connection)
does not cancel the pending stop. A restart issued shortly after such a
stop was triggered can look like it succeeded, only for the original
delayed stop to land later anyway and undo it.

Consequences for any script or check that issues a graceful stop with a
timeout:

- **Never kill the calling process before it returns.** Give it a timeout
  generous enough to let the operation actually finish (ten minutes, not
  two), rather than risk leaving a stop in flight with no client left
  watching it.
- **Capture and restore every affected resource, not just the one you meant
  to stop.** The incident here happened in part because the restoration
  logic captured and restored daemon and cluster-service state, but never
  server `isActive` state - stopping a daemon also drops its server's
  `isActive` flag, a dependency that was not obvious until it was missed.
- **Verify twice, with a real wait in between**, roughly matching the
  timeout that was passed plus margin, specifically to catch a delayed stop
  that was still pending when the first verification looked clean.

## Triggering a real transfer: POST /transfers/operations?operation=pull

Confirmed directly: this is the actual call that makes an account pull files
from one of its own sites - the mechanism `customProperties` (see the
Expression Language section above) is documented against, and the one
`90.EndToEndAcknowledgment/Acknowledgment.sh` needs a real transfer to exist
before it has anything to acknowledge. The body is `{accountName, site,
destinationDirectory, transferProfile, customProperties, awaitResult}` -
`transferProfile` is required specifically for PeSIT transfers, per its own
schema description. A successful call returns 202 (accepted, asynchronous),
with a `link` back to `/logs/transfers?operationIndex=...` to poll for the
result - not the transfer record itself.

**With no filename specified, what a PeSIT pull fetches comes from the
sender's transfer profile, `sendMapping`.** Two different results were seen
with `sendMapping: "/*"`. On a long-standing pair of accounts, the pull fetched
an arbitrary real file out of the sending account's home folder. On a pair
created through the API, the sender looked for a file literally named `*`
and answered "File not found" (`realFile /home/<account>/*`). Name the file
in `sendMapping` (`/pesit_loop.txt`) when the test needs to know what it
sends. The
*local filename* it lands under, by contrast, was completely deterministic
- the receiving transfer profile's `receiveMapping: "/${pesit.fileName}"`
evaluated to the literal string `"TP"` (the transfer profile's own name)
every single time, regardless of what the source file was actually called.
Do not assume "the destination filename is predictable" means "the content
is too," or the reverse.

`storeAndForwardMode: "PRESERVE"` on a site means exactly what it says:
confirmed directly, the sending account's own file listing was unchanged,
byte for byte, before and after a pull - the source file is copied, not
moved.

Sending an ACK or NACK is not a side-effect-free status flip on the original
transfer record. Confirmed directly: `POST
.../logs/transfers/{id}/operations?operation=nack` (and, presumably, `ack`)
creates its own additional logged sub-transaction sharing the same
`coreId`, on top of setting `pesitAckStatus` on the original entry. A
coreId-filtered `GET /logs/transfers?coreId=...` query returns the ordinary
`{"result": [...]}` shape every other `/logs/transfers` listing does -
`"pullEntries"` is specific to the `operationIndex`-tracking query used to
watch one just-submitted pull, not a general property of this endpoint.

## A PeSIT loop on one server, built through the API

Confirmed directly, building `32.pesit_acknowledgment_loop_scripts.py`. Two
accounts can send each other files over PeSIT on one server: each has a PeSIT
site named after the **other** account (the account name is its PeSIT
partner identifier, so keep it short and alphanumeric), pointing at the
server's own PeSIT listener (17617), and each has a default transfer profile.

- **A PeSIT site created through the API leaves ten fields empty** that a site
  made in the admin UI fills in: `dmz` ("none"), `pesitId` (""),
  `ptcpConnections` (1), `socketSendReceiveBuffersize` (65536),
  `receiveMessage` and `sendMessage` (""), and the four `use...PasswordExpr`
  flags (false). With them empty, the pull is accepted (202) and never
  connects - no transfer is logged at all. Set them.
- **`awaitResult: "true"`** turns any failure into an immediate 400
  "Transfer triggered from admin pull event failed." with no detail. Pull
  with `awaitResult: false` and read the `pullEntries` of its
  `operationIndex`; a failed entry's own record (`GET` its `self` link) has
  the PeSIT exchange and the error.
- **A relative `receiveMapping`** (`${pesit.fileName}`) lands the file in the
  pull's `destinationDirectory`. An absolute one (`/${pesit.fileName}`) lands
  it in the home folder, whatever the pull asked for.
- **The sender's outbound and the receiver's inbound have different
  `coreId`s.** So a plain pull has no outbound under the receiver's `coreId`,
  and `Acknowledgment.sh` sends a NACK. For an ACK, something must push the
  received file on - a subscription on the landing folder and a route.
- **Deleting the received file counts as that outbound.** An End User API
  delete is logged as an outgoing transfer under the file's `coreId`, and
  `Acknowledgment.sh` then sends an ACK. Acknowledge before cleaning up.
- **An ACK or NACK sent after the account is deleted** is answered 200 and not
  recorded: the transfer stays unacknowledged in the log.

## Resetting a real account's password without losing the original

Confirmed directly: `passwordDigest` under `user.passwordCredentials` is not
just a read-only artifact `GET` happens to return - the Admin API's own
schema documents it as a settable `PATCH` field in its own right ("if
passwordDigest is specified password policies will not be applied"). That
means a real account's password can be temporarily changed (`PATCH .../user
/passwordCredentials/password` with a plaintext value, to get a working
login) and then restored **exactly**, bit for bit, by writing the original
`passwordDigest` value straight back - confirmed directly, by reading it
back afterward and comparing to what was captured before. This is the only
way found so far to get a working login on an account whose real password
is unknown, without permanently changing it.

## The admin API has no file-browsing or file-delete endpoint of its own

Confirmed by checking the full OpenAPI spec: nothing under `/files` or
similar exists on the Admin API side. Reading or deleting a specific file in
an account's home folder needs a real login to the EndUser API for that
account - the admin API can create, patch and delete the *account*, but has
no visibility into what is actually sitting in its home folder.

# Part 2: scripting traps

## Never edit JSON with a text substitution

This is the trap that cost the most here. A `sed`, or a PowerShell `-replace`,
over a JSON document looks like it works and quietly corrupts the object. Tested
against a real server response, one such line:

- failed to change `port`, because the pattern assumed a space after the colon
  (`"port": ` versus `"port":`)
- **deleted a sibling object**, because `.*` ate the rest of the line
- mangled unrelated free text, because the name was replaced globally
- still produced valid JSON, so the server accepted the damaged object

Use `jq` in bash and `ConvertFrom-Json` / `ConvertTo-Json` in PowerShell. They
target the field and always emit valid JSON.

```bash
jq --argjson newPort "${NEW_PORT}" '.port = $newPort' tmp.json > tmp.json.new && mv tmp.json.new tmp.json
```

```bat
powershell -Command "$j = Get-Content -Raw 'tmp.json' | ConvertFrom-Json; $j.port = %NEW_PORT%; $j | ConvertTo-Json -Depth 100 | Set-Content 'tmp.json'"
```

Use a generous `-Depth` on `ConvertTo-Json`; the default is 2 and silently
flattens nested objects.

## curl -w output captured into a variable is not just the body

```bash
result=$(curl -w "%{http_code}" -s -o /dev/stdout ... )
echo "${result}" > downloaded_file    # wrong: the status code's digits are
                                       # now stuck on the end of the file
```

Confirmed as a real, shipped bug: this pattern was in both EndUser file
download examples, silently appending the HTTP status code to the end of
every downloaded file's content. `${result: -3}` correctly pulls the status
back out for checking, but printing or writing `$result` itself still includes
it. Give the body and the status separate destinations instead:

```bash
http_status=$(curl -w "%{http_code}" -s -o downloaded_file ...)
```

`-o` writes the body straight to its destination - a file or `/dev/null` -
and stdout then holds only what `-w` prints, so nothing needs to be split
back apart.

What `-w` writes has no newline at the end unless the format adds one. Read
line by line, `while IFS= read -r line` silently skips that last line.
Confirmed as a shipped bug: `Acknowledgment.sh` never saw its `HTTPC=200`
line, and logged every ACK and NACK it sent as failed. Keep the last line
with:

```bash
while IFS= read -r line || [[ -n "$line" ]]; do
```

## Single-quoted shell payloads do not expand variables

```bash
-d '{"host":"${ST_SERVER}"}'     # sends the literal ${ST_SERVER}
-d "{\"host\":\"${ST_SERVER}\"}" # correct
```

The server accepts the literal string, so this fails silently as a bad
configuration rather than as an error.

## PowerShell renders booleans as True and False

`(ConvertFrom-Json).isActive` stringifies to `True` or `False`, not the JSON
`true` / `false`. So in a batch file:

```bat
IF "%IS_ACTIVE%"=="false"   REM never matches
IF "!IS_ACTIVE!"=="True"    REM correct
```

With `jq -r` in bash you do get lowercase `true` / `false`.

## jq without -r keeps the quotes

`jq '.sshStatus'` yields `"Not running"` **including the quotes**, so a
comparison against `Not running` fails. Use `jq -r`.

## Batch: delayed expansion inside a block

A variable set inside a parenthesised `FOR` or `IF` block cannot be read with
`%VAR%` in the same block — that is expanded once when the block is parsed.

```bat
SETLOCAL ENABLEDELAYEDEXPANSION
FOR /L %%i IN (0,1,%LAST%) DO (
    FOR /F "tokens=*" %%A IN ('...') DO SET NAME=%%A
    echo !NAME!          REM not %NAME%
)
```

Safer still, and the pattern preferred here: put the body in a `CALL :subroutine`.
Each `CALL` is its own statement, so ordinary `%VAR%` expansion works and the
trap disappears.

Also: `.Count` gives a count, so the last index is `count - 1`. Use
`SET /A LAST=%COUNT%-1`.

## sed -i is not portable

`sed -i ''` is BSD (macOS); GNU sed reads `''` as the script and fails. Since ST
runs on Linux, this breaks the examples for most of the audience. Avoid in-place
`sed` entirely — use `jq` (see above).

## PWD is a shell builtin

Do not name a password variable `PWD`; bash keeps the working directory there.
It appears to work until a script adds a `cd`, then authentication breaks for a
reason nobody will guess. That is why the variables here are `ST_*`.

## Resolve paths from the script, not the working directory

```bash
SCRIPT_DIR=$(dirname "$(realpath "$0")")
source "${SCRIPT_DIR}/../set_variables.sh"
```

`source "../set_variables.sh"` only works if you have `cd`'d into the script's
folder first.

In python, the same rule:

```python
configFile = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'config')
```

## Git pathspecs are case-sensitive

`git ls-files "*.sh"` does not match a file named `.SH`. One file in this
repository had an uppercase extension and was silently skipped by a repo-wide
rename and by every syntax check afterwards. When sweeping the tree, match
case-insensitively and confirm the file count.

## Quote paths: this repository has spaces in them

Every path contains `API 2.0`. Unquoted `$(git ls-files ...)` in a `for` loop
word-splits on that space and silently processes nothing. Use `-z` with
`xargs -0`, or quote carefully.

## multiprocessing.Process silently loses your globals on macOS and Windows

A module global set only inside `if __name__ == "__main__":` is not visible
inside a function run via `multiprocessing.Process`, unless every platform
this runs on defaults to fork. Confirmed directly, running the real
`stBuildTestAccounts.py` and `stDeleteTestAccounts.py`: their worker
functions call a shared `stLogin()`/`stLogout()` helper that reads `stUrl`,
`referer`, `stTimeout` and a shared counter as plain module globals rather
than as arguments - fine on Linux, whose default start method is `fork`
(the child is a copy of the already-running parent, globals and all), but a
`NameError` on macOS and Windows, whose default is `spawn` (the child
re-imports the module fresh, so anything set only inside the parent's
`__main__` guard was never set in the child at all).

If a function is going to run in its own process, either pass it everything
it needs as arguments and have it use only those - not a same-named helper
that reaches for a global - or seed the globals explicitly at the top of the
function via `globals()['name'] = value` before calling anything that
depends on them (works because `global name` cannot coexist with a parameter
of the same name, which is exactly the shape this trap takes: the value
you need is sitting right there in the argument list).

A third python3 example had a real, similarly-shaped CSRF bug, found while
looking for one to write an integration test for:
`stGetPrivateCert.py` keeps a session cookie (`requests.Session()`) across
its login, its one certificate export call, and its logout - but never
captured or sent a `csrfToken` at all, on any of the three. Fixed the same
way the cookie-based bash examples were: capture the token once from the
login response, send it back on every later call. Confirmed working
end-to-end for the login/logout half (a deliberately wrong certificate ID
gets a real 400 back, not a CSRF rejection) - the export call itself could
not be exercised for real, because this server has zero certificates of
usage `private` to read, and there is no way to manufacture one without the
server's own CA password (see above).

Also confirmed in the same two scripts: a missing `import base64` at module
level - `NameError: name 'base64' is not defined` the moment the main block
tried to use it, present only inside one function's own separately-scoped
import, which does not help the module level code that runs before any
function is ever called.

## os.sched_getaffinity is Linux only, despite os.name == 'posix'

`os.name == 'posix'` is true on macOS and BSD too, but `os.sched_getaffinity`
only exists on Linux - confirmed directly: `AttributeError: module 'os' has
no attribute 'sched_getaffinity'` on macOS, in four of the python3 examples
that print it as an FYI. Guard with `hasattr(os, 'sched_getaffinity')`
alongside the `posix` check, not instead of it.

# Part 3: habits that paid off

- **Dry run first.** Anything that writes to many objects should be able to show
  what it would send without sending it. The bulk python scripts default to it.
- **Read before you write.** GET the object, confirm the field and the shape, then
  PATCH or PUT. Most 422s are a guess about the current state.
- **Check the status code, not the body.** PATCH and PUT return no body.
- **Test the payload, not the script.** Point `curl` at a stub that prints the
  `-d` argument, then validate that it is the JSON you intended. That is how the
  silent `sed` corruption above was found.
