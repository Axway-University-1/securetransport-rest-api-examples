# Changing objects through the REST API without breaking them

**For:** administrators and integrators who change accounts, routes, sites, settings and other objects with PATCH and PUT.
**Checked on:** SecureTransport 5.5-20260924. Where the text says "the server does" or "tried", it was run on this version with throwaway objects. The objects were
removed afterwards, and every setting that was changed was put back and compared. A statement marked "not tried" comes from the example scripts of this
repository or from the product notes, and was not run here. In this guide, "the lab" is the test server that it was checked on.

## Summary

There are two ways to change an object: **PATCH** changes a few fields, and **PUT** replaces the whole object. Both can break something quietly.

- Read the object first. Check the result afterwards. A `204` says the server accepted the request, not that the object is what you wanted.
- Use PATCH for a small change to a field you know is there. Use PUT, with the whole object you read, for several changes, or when the order of a list matters.
- Never send PUT with a hand-made part of an object. Every field you leave out is reset. Tried on a route: the steps disappeared.
- Send `Content-Type: application/json`. Without it the answer is `415`.
- Build the JSON with `jq` or a JSON library. Never edit it with `sed` or text substitution.

## PATCH or PUT

| | PATCH | PUT |
| - | ----- | --- |
| What it sends | A list of operations (JSON Patch): `replace`, `add`, `remove` | The whole object |
| What it changes | Only the fields you name | Everything: a field you leave out is reset |
| When to use it | One or two fields that you know exist | Many changes at once, or a list whose order matters |
| Risk | A typo in a path may do nothing, or fail | A field you forgot is lost |

## PATCH: the three operations

A PATCH body is a **list** of operations. Each has `op`, `path` and, for `replace` and `add`, `value`. These cases were tried on a throwaway account
that had `contact.email` and an empty `contact.phone`. The call is:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/ZZTEST_example" \
  -H "accept: application/json" -H "Content-Type: application/json" -H "Referer: x" \
  -d '[{"op":"replace","path":"/contact/email","value":"new@example.com"}]'
```

The answer is `204`, with no body.

| Operation | What was tried | Answer | What is in the object afterwards |
| --------- | -------------- | ------ | -------------------------------- |
| `replace` | A field that has a value (`/contact/email`) | 204 | The new value |
| `replace` | A field the object always carries, with the value `null` (`/contact/phone`) | 204 | The new value |
| `replace` | A field the object does not have (`/nosuchfield`, tried on a route) | **400** `Missing field "nosuchfield"` | Nothing changed |
| `add` | `/contact/phone` | 204 | The value is set |
| `add` | A field the object does not have (`/nosuchfield`, tried on a route) | **204** | Nothing: the name is not stored, and no error is shown |
| `remove` | `/contact/phone` | 204 | The field is still in the answer, now with the value `null` |

Four things follow:

- **`replace` needs the field to exist, and `add` creates it.** When you do not know whether a field is set, read the object first. (`add` on a field that already
  has a value may replace it, refuse it or duplicate it, depending on the resource. This comes from the notes of this repository and was not tried.)
- **A typo in an `add` path is not an error.** It answers 204 and changes nothing. Read the object back.
- **`remove` does not delete the field from the answer.** It sets the value to `null`. When you check the result, test for `null`, not for a missing key.
- **A patch is all or nothing.** Two operations were sent together, the first valid and the second on a field that does not exist. The answer was 400, and the
  first one was **not** applied.

### What the server says about a wrong request

| Request | Answer |
| ------- | ------ |
| A PATCH without `Content-Type`, or with `text/plain` | **415** "HTTP 415 Unsupported Media Type" |
| One operation, not in a list: `{"op":...}` | **400** "Incorrect JSON format" |
| An operation that does not exist: `{"op":"swap",...}` | **400** "unknown / unsupported operation swap" |

## Lists, and route steps

A path into a list takes a **position**, counted from 0. It never takes an id. Tried on a route with two steps:

| Operation | Answer | Result |
| --------- | ------ | ------ |
| `add` at `/steps/1` | 204 | The step is inserted in the middle. The `precedingStep` of the next step now points at the new one. |
| `add` at `/steps/-` | 204 | The step is added at the end. |
| `replace` at `/steps/2/status` | 204 | The status of the third step changes. |
| `add` at `/steps/9`, past the end | **400** "Array index 9 out of bounds" | Nothing changed |
| `replace` at `/steps/` followed by the step's **id** | **400** `Can't reference field "…" on array` | Nothing changed |

A step has an `id`, and the answer shows a `precedingStep` link, but a path takes the position of the step. So read the route, find the position of the step you
want, and build the path from it. `jq` can find it:

```bash
jq '.steps | map(.fileFilterExpression) | index("*.two")' route.json
```

For a route whose steps have a `fileFilterExpression`, this prints the position of the step with that filter. Do not assume a position: steps can be added and moved.

The `-` at the end of a path means "add at the end". On this route it is the end. On some other lists it is not promised. The notes of this repository say that the new rule goes first in `/rules/-` of a login restriction policy (not
tried here). When the order matters, read the list back.

## PUT: send back the whole object

PUT replaces the object. The safe way is always the same: read the object, change **your copy**, send the copy back.

```bash
# 1. read the route and keep the copy, 2. change the copy with jq, 3. send the copy back
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes/ROUTE_ID" \
  -H "accept: application/json" -H "Referer: x" > route.json
jq '.description = "changed by a script"' route.json > route_new.json
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes/ROUTE_ID" \
  -H "accept: application/json" -H "Content-Type: application/json" -H "Referer: x" \
  --data-binary @route_new.json
```

Replace `ROUTE_ID` with the id of the route. What was tried on a route that has two steps:

| What was sent | Answer | Result |
| ------------- | ------ | ------ |
| The object exactly as it was read, with one field changed | 204 | The change, and the steps are as they were |
| The same, without `metadata` | 204 | The same |
| The same, without the route's own `id`, but with the `id` of each step | **400** "Cannot attach a route step to another route" | Nothing changed |
| The same, without the `id` and `precedingStep` of each step | 204 | The change was applied |
| **A fragment:** only `name`, `type`, `conditionType` and `description` | 204 | **The two steps are gone.** |

Send back what you read, with the `id` as it was. Never send a fragment: the server does not warn you that it removed something. (From the notes of this
repository, not tried here: the same happens to transfer sites, subscriptions, zones, transfer profiles and user classes.)

The example `Admin/API 2.0/python/python3/stUpdateRouteWithPut.py` in this repository does the read, change and write for a route.

## The server checks the whole object

When you change an object, the server validates the **whole** object, not only your change. If the stored object is already inconsistent, even a PATCH that
changes nothing is refused. Tried on the login settings of the lab, which have `certificateIssuer` set to `other` and no `adminCertificateFileOrPath`:

```text
PATCH /configurations/loginSettings   [{"op":"replace","path":"/requirePassword","value":"optional"}]    (the value it already has)
->  400  You must specify adminCertificateFileOrPath when certificateIssuer is set to other.
```

The message names a field you did not touch. When a harmless change is refused, read the message. The cause may be in another field of the same object.
Fix that field first, or in the same request.

## Configuration options

A server option is read and written at `/configurations/options`. The answer for one option, found with `?name=`, has a `values` list and more, among them
`defaultValues`, `readOnly` and `specified`.

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations/options" \
  --data-urlencode "name=AddressBook.Limit.MaxDisplayEntries" -H "accept: application/json" -H "Referer: x"
```

```text
{ "result" : [ { "name" : "AddressBook.Limit.MaxDisplayEntries", "values" : [ "100" ], "defaultValues" : [ "100" ], "readOnly" : false, ... } ] }
```

To change it, send a **list** of objects, each with `name` and `values`, to PUT. The values are a list of text:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations/options" \
  -H "accept: application/json" -H "Content-Type: application/json" -H "Referer: x" \
  -d '[{"name":"AddressBook.Limit.MaxDisplayEntries","values":["77"]}]'
```

The answer is `204`. Tried, and each time the option was read back:

| What was sent | Answer |
| ------------- | ------ |
| `values` as a list of text: `["77"]` | 204, the option is `["77"]` |
| `values` with a number: `[78]` | 204, the option is read back as the text `["78"]` |
| `value` (one, not `values`) | **400** "Unsupported parameter" |
| One object, not a list | **400** "Incorrect JSON format" |
| An option that does not exist | **404** "Configuration options with name(s) No.Such.Option not found" |
| PATCH on `/configurations/options` | **405** |

**Save the option before you change it, and compare after you put it back.** Save the whole answer, not only the value. After the restore the answer for the
option must be the same as the saved one.

## A complete example: read, change, check, restore

This changes the email address of a throwaway account, and puts it back. It uses `jq` to build every body, so no text is edited by hand.

```bash
ACCOUNT=ZZTEST_example
API="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}"
call() { curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -H "accept: application/json" -H "Referer: x" "$@"; }

call "${API}" > before.json                                              # 1. read, and keep the copy
jq -n --arg v "new@example.com" '[{op:"replace", path:"/contact/email", value:$v}]' > patch.json
call -X PATCH -H "Content-Type: application/json" --data-binary @patch.json "${API}"    # 2. change: 204
call "${API}" > after.json                                               # 3. read again
jq -r '.contact.email' after.json                                        #    check: new@example.com
jq -n --slurpfile b before.json '[{op:"replace", path:"/contact/email", value:$b[0].contact.email}]' > undo.json
call -X PATCH -H "Content-Type: application/json" --data-binary @undo.json "${API}"     # 4. restore from the copy
call "${API}" > restored.json
diff <(jq -S . before.json) <(jq -S . restored.json) && echo "the account is as it was"
```

## Do not edit JSON with text substitution

A value can hold any character: a quote, a backslash, an ampersand, a dollar sign. A text tool does not know that it is inside JSON, and it makes a body that is
broken, or one that means something else. A tool for JSON handles it:

```bash
NEW='Smith "the boss" & Co'
echo '{"name":"x"}' | sed "s/x/${NEW}/"         # {"name":"Smith "the boss" x Co"}   not JSON: the quotes break it, and & became x
jq -nc --arg v "$NEW" '{name: $v}'                  # {"name":"Smith \"the boss\" & Co"}  JSON
```

In Python, use `json.dumps` or the `json=` argument of `requests`. In PowerShell, use `ConvertTo-Json`.

## Checklist

- [ ] The object was read first, and a copy was kept.
- [ ] PATCH only for fields known to exist. A list is addressed by position, found in the object just read.
- [ ] PUT only with the whole object as it was read, with its `id`. Never a fragment.
- [ ] `Content-Type: application/json` is sent, and the PATCH body is a list.
- [ ] The object was read again afterwards, and the result is what was meant. A `204` is not proof, and `remove` leaves `null`.
- [ ] A 400 that names a field you did not touch is looked at: the whole object is validated.
- [ ] An option was saved whole before the change, and compared after the restore.
- [ ] Every body was made by `jq` or a JSON library.
