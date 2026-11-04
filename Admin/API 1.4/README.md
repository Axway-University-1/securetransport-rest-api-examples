# Admin API 1.4 examples

> **For test environments only.** Read the [Disclaimer](../../README.md#disclaimer) before you run anything. The settings
> (`ST_SERVER`, `ST_PORT`, `ST_USER`, `ST_PASSWORD`) are the ones of [Configuration](../../README.md#configuration): copy
> `bash/set_variables.local.example.sh` to `bash/set_variables.local.sh` and fill it in.

SecureTransport 5.5 still serves the older Admin API 1.4 next to 2.0 (`https://<server>:<port>/api/v1.4/docs/index.html` is its Swagger page). **This folder
is not a second copy of the 2.0 examples.** It holds only what 1.4 can do and 2.0 cannot, so that you do not have to search the old reference for it.
Everything else that 1.4 does has an answer in 2.0: [Admin/API 2.0](../API%202.0/README.md).

The examples are bash only (`curl` and `jq`), with no bat twins.

## What 1.4 has and 2.0 has not

The two references were compared operation by operation (the 1.4 spec of the lab is the same file as the public one), and what looked missing was tried on a lab server.

| What | 1.4 | In 2.0 | Example |
| ---- | --- | ------ | ------- |
| Check a path on the server: valid, outside the unsafe list | `POST /validation/validPath` | nothing | [01.Validation/01](bash/01.Validation/01.validation_validPath_POST.sh) |
| Ask the server about a path: valid, exists, is a folder, is a file | `POST /validation/path` | nothing | [01.Validation/02](bash/01.Validation/02.validation_path_POST.sh) |
| Resubmit many transfers with one call, by search criteria | `POST /transfers/resubmit` | one transfer at a time, `POST /logs/transfers/{id}/operations?operation=resubmit` | [Admin use case 09](../UseCases/09-resubmit-transfers/README.md) (both ways) |

## What 1.4 shows that 2.0 shows differently

These looked like gaps. They are not: 2.0 has them in another place, and each was tried.

| In 1.4 | In 2.0 |
| ------ | ------ |
| The users of an account: `/accounts/{name}/users` | One user only, in the `user` object of the account (1.4 also answers "only one user is allowed") |
| Address book sources of an account or business unit, and its contacts | `addressBookSettings` of the account and of the business unit: `policy`, `sources`, `contacts`, `nonAddressBookCollaborationAllowed` (on user and template accounts; the reference gives it to a business unit too). Tried on a user account: a `PATCH` that replaces it must send all the sources, and the contact that 1.4 would not take as JSON was added this way. |
| Convert an account to licensed | The `unlicensed` field of the account |
| Unique file transfers of today: `/transfers/uniqueFileTransfersCount` | `GET /statisticsSummary/generateReport` for today (`ST.TransfersIn`, `ST.TransfersOut`, `ST.Transfers`), or the count of `GET /logs/transfers` with `isBillable`. Tried with 100 uploads: 1.4 said 100 incoming, 0 outgoing, and so did 2.0. See [Admin use case 07](../UseCases/07-usage-reporting/README.md). |
| Duplicate a certificate: `/certificates/{id}/duplicate` | Export it as PKCS#12 (`/certificates/{id}/operations?operation=export&format=pkcs12`) and import the file under a new name. The copy has the same serial number as the 1.4 duplicate. |
| The steps a composite route inherits from a template | `routeTemplate` and `stepStatuses` of the route |
| The members of an administrative role | `GET /administrators?roleName=` |
| The access level of a certificate | The `accessLevel` field |
| A schedule, an edge, a rule, a step, a menu | Inside the object, changed with `PATCH` |

## Still without a 2.0 answer, not covered here

- **The list of audited object types** (`/auditLog/objectTypes`, 20 types). 2.0 has the `objectType` filter of `GET /logs/audit` but no list of the valid values; the types that appear in the log can be read from it.
- **The certificates and signing requests of a zone edge**: the 1.4 call answered 403 on the lab, so it could not be tried.

## What 1.4 does oddly

Tried on 5.5-20260924: `/daemons/status` answers 500, `/sessions/count` answers 406, `/routes/count` answers 400 unless a route type is given, and a POST of the contacts of an account answers "Incorrect JSON format" for every shape tried. Use 2.0 for these.

## 1.4 in short

- The base URL is `/api/v1.4`. Basic authentication works, with a `Referer` header, as in 2.0.
- A list is not `{resultSet, result}` but an object with the list under a name (`transferEntries`, `addressBookSources`), each entry wrapped once more (`transferEntry`).
- A change of an object is a `POST` to the object (2.0 uses `PATCH`).
- A call that takes form data answers 415 when sent as JSON.
