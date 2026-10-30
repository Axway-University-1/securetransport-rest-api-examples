# 05 Changing an object

**Use case:** an administrator changes objects that already exist: an account, a route, a server setting. Two requests do it. **PATCH** changes the fields you name, and **PUT** replaces the whole object. This use
case runs both on throwaway objects, step by step, and shows for every change the body that was sent, the answer, and the object before and after.

The thing to learn here is that **a PATCH is written differently for each type of value**: a text, a number, a true/false value, a list and a nested object each take their own form. Step 02 shows the type of every field
before a step changes it. Steps 03 to 07 take one type each.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`Admin/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).
> Everything here is changed on objects that this use case makes (an account `NAME` and a route `NAME_route`, `example_chg` by default). One server setting, an option of the address book, is changed for a moment in
> step 11 and put back exactly; `99.cleanup_DELETE.sh` puts it back even when step 11 was stopped half way.

## What to write for each type

A PATCH body is always a **list** of operations. Each has `op` (`replace`, `add` or `remove`), a `path`, and for `replace` and `add` a `value`. What changes with the type is the value, and what the path points to.
Checked on SecureTransport 5.5-20260924.

| Type of the field | The value you write | Operations | Example body | Answer | What to check afterwards |
| ----------------- | ------------------- | ---------- | ------------ | ------ | ------------------------ |
| **String** (text) | In double quotes: `"first note"` | `replace`, `add`, `remove` | `[{"op":"replace","path":"/notes","value":"first note"}]` | `204` | `remove` leaves the field in the answer with `null`. The empty text `""` is stored as `null`. A number sent to a text field is stored as text (`5` becomes `"5"`). A list is refused (`400`). |
| **Number** | No quotes: `5` | `replace`, `remove` | `[{"op":"replace","path":"/user/failedAuthMaximum","value":5}]` | `204` | Read it back. `"7"` is accepted and stored as `7`, and `2.5` is stored as `2`, both without a word. `"abc"` and a value below the minimum are `400`. `remove` puts the default back (`3`) when there is one, and `null` when there is not. |
| **Boolean** (true or false) | No quotes: `true` or `false` | `replace`, `remove` | `[{"op":"replace","path":"/transfersWebServiceAllowed","value":true}]` | `204` | `"false"` and `1` are accepted and converted. `"yes"` is `400`. `null` is `400` on `disabled`. `remove` puts `false` back. |
| **List** | The whole list, `[ ... ]`, or one **whole item**. A path to an item ends in its **position**, counted from 0, never in its id | `replace` (the list or one item), `add` (`/-` at the end, `/N` at a position), `remove` (`/N`) | `[{"op":"add","path":"/steps/-","value":{ ...a whole step... }}]` | `204` | Read the list: the order and the count. A position past the end and an id in the path are `400`. `remove` on `/steps/-` answers `204` and removes nothing. |
| **Object** (nested) | The whole object, `{ ... }`, or one field inside it by its path | `replace` (the object or one field in it), `remove` | `[{"op":"replace","path":"/bandwidthLimits","value":{"policy":"custom","inboundLimit":100}}]` | `204` | **What the new object leaves out is reset to `null`.** `remove` leaves the object in the answer with every field `null`. `null` in place of an object is `400`. |
| **Null** | `null` | `replace`, `remove` | `[{"op":"replace","path":"/contact/email","value":null}]` | `204`, or `400` | The field is cleared when it may be empty. It is `400` when it must have a value (`disabled`). |

Four rules hold for every type:

- **`replace` needs the field to exist, and `add` creates it.** A field that is `null` in the answer exists, so `replace` works on it. `replace` of a field the object does not have is `400` `Missing field`.
- **A typo in the path of an `add` is not an error.** It answers `204` and stores nothing (step 08).
- **A patch is all or nothing.** Two operations, the second wrong: the answer is `400`, and the first is not applied (step 08).
- **A `204` says the server accepted the request, not that the object is what you meant.** Read it again, as every step does. The server is generous with types in this release (a number in quotes, a decimal for a whole number), and another
  release may be stricter. Write each type as the table shows, and the script keeps working.

## The examples

Run them in order (`00.run_all.sh` runs them all and ends with `99.cleanup_DELETE.sh`). Every script takes the name of the account as its first parameter, `example_chg` when it is left out, and works on the route `NAME_route`.
The name **must start with `example_`**: 99 deletes by name, and this keeps it off a real object. Step 11 takes the option and a value instead.

| Script | What it does | Copied from |
| ------ | ------------ | ----------- |
| `01.object_POST [NAME]` | Makes the account `NAME` (text, numbers, booleans, nested objects) and the route `NAME_route` with two steps (a list). An object that exists is not made again. The id of the route comes from the `Location` header. | `Admin/API 2.0/bash/05.Accounts/02.accounts_POST.sh` and `09.CompositeRoutes/03.routes_POST_simple_compress.sh` |
| `02.object_GET [NAME]` | **Read first.** Reads both, keeps a copy of each (`state.local.account.json`, `state.local.route.json`) and shows the fields the next steps change, each with its JSON type. | `05.Accounts/04.accounts_name_GET.sh` and `09.CompositeRoutes/06.routes_GET.sh` |
| `03.patch_string [NAME]` | A **string**: replace on a text that is `null`, replace on a text that has a value, add, remove, a number sent to a text field, a list sent to a text field, the empty text. | `05.Accounts/06.accounts_name_PATCH.sh` |
| `04.patch_number [NAME]` | A **number**: no quotes, in quotes, a text, a decimal, below the minimum, `remove`; a limit that is `null` until it is set; `uid`, which looks like a number and is text. | written for this use case |
| `05.patch_boolean [NAME]` | A **boolean**: `true`, `"false"`, `"yes"`, `1`, `remove`, `null`; the same on a second boolean (`authByEmail`). | written for this use case |
| `06.patch_list [NAME]` | A **list** (the steps of the route): add at the end, add at a position, replace an item and one field of an item, remove by position, find the position with `jq`, the mistakes (past the end, an id in the path, a text for the list, `remove` of `-`), replace the whole list. | `09.CompositeRoutes/10.routes_id_PATCH.sh` |
| `07.patch_null_and_object [NAME]` | A **null** and a nested **object**: replace with `null`, replace a whole object, a fragment of one, one field inside it, `remove`, `null` for an object. | written for this use case |
| `08.patch_mistakes [NAME]` | What goes wrong: a patch that is all or nothing, a typo in the path of an `add`, `replace` of a field that is not there, a body that is not a list, an operation that does not exist, no `Content-Type`, `text/plain`. | `05.Accounts/06.accounts_name_PATCH.sh` |
| `09.put_whole_object [NAME]` | **PUT** the object you read, with one field changed. Proves that only that field differs. Then without `metadata`, and without the route's own `id` (refused). | `09.CompositeRoutes/09.routes_id_PUT.sh` |
| `10.put_fragment [NAME]` | **PUT** a fragment: the two steps of the route are gone, with a `204`. Then the way back: the saved copy is refused, and a PATCH that replaces the list puts the steps back. | written for this use case |
| `11.options_save_change_restore [OPTION] [VALUE]` | A **server setting**: saves the option as it is, changes it (a list of objects with `name` and `values`), tries the shapes the server refuses, puts it back and compares it with the saved copy. | `13.Configurations/04.configurations_options_PUT.sh` and `06.configurations_options_name_GET.sh` |
| `99.cleanup_DELETE [NAME]` | Puts the option back if step 11 left it changed, deletes the route and the account if they are still there, removes the state files and ends the administrator's session. Can be run twice. | |

`lib.sh` is the shared file: it loads `../session.sh` (the settings, the Admin session in `session.cookie.jar`, which git ignores) and has the helper every case of 03 to 08 uses. It sends one PATCH and prints the body, the value
before, the answer (and the server's message when it refuses), and the value after. It ends the step with exit 1 when the answer or the value after is not what this README says: the line `NOT AS DOCUMENTED` names the case.
That is how you notice that another release behaves differently.

## What each step shows

### String (03)

A text is a JSON string, in double quotes. The field `notes` is `null` after step 01, and `replace` works on it because the field is in the answer. `add` sets a field in the same way. `remove` does not take the field out of the
answer: it is there, with `null`. A number sent to a text field is stored as the text of the number. The empty text is stored as `null`, so a field you "cleared" with `""` and one you cleared with `null` look the same afterwards.

```
--- a NUMBER sent to a text field is stored as text
  body:    [{"op":"replace","path":"/notes","value":5}]
  before:  "first note"
  answer:  HTTP 204
  after:   "5"
```

### Number (04)

A number is written with no quotes. The server converts `"7"` to `7` and cuts `2.5` to `2`, both with a `204`, so a script that sends the wrong form works and stores something you did not mean. A text that is not a number is
refused with `Cannot parse 'abc' to Integer.`, and a value below the minimum with `user.failedAuthMaximum must be greater than or equal to 0`. `remove` is not "make it empty": a number that has a default goes back to the default
(`failedAuthMaximum` is `3`), and one that has none (`inboundLimit`) is `null` again.

The account has a field that looks like a number and is **text**: `uid` is `"54321"`. Send it `60000` and the server stores `"60000"`. When you write a patch for a field, look at its type in step 02, not at what the value looks like.

A limit needs its policy: `bandwidthLimits.inboundLimit` is only kept when `bandwidthLimits.policy` is `custom`, so the step sends both in **one** patch, two operations.

### Boolean (05)

`true` and `false` with no quotes. The server converts `"false"` and `1` and refuses `"yes"` (`Cannot parse 'yes' to Boolean.`). `remove` sets `false`. `null` is refused on `disabled` (`isDisabled must not be null`).
A boolean that is `false` after a `remove` looks like one you set to `false`: the server does not say it was a default.

### List (06)

The steps of the route are a list of objects. A path into it ends in a **position**, counted from 0:

| Operation | Path | What happens |
| --------- | ---- | ------------ |
| `add` | `/steps/-` | The item is added at the end. |
| `add` | `/steps/0` | The item goes to position 0 and the ones after it move down. |
| `replace` | `/steps/1/fileFilterExpression` | One field of the item at position 1 changes. |
| `replace` | `/steps/0` | The whole item at position 0 is replaced. |
| `remove` | `/steps/0` | The item is removed and the ones after it move up. |
| `replace` | `/steps` | The whole list is replaced by the list you send. `[]` removes every step. |
| `add` | `/steps/9` (past the end) | `400` `Array index 9 out of bounds`. |
| `replace` | `/steps/<id>/status` | `400` `Can't reference field "<id>" on array`. A step has an `id`, but a path takes its position. |
| `remove` | `/steps/-` | `204`, and nothing is removed. |

The value of `add` or of `replace` on an item is a **whole item**: here a whole route step, which the step builds with `jq`. Do not assume a position: **read the route and find the step**, as the step does
(`index("*.two")` on the list of filters), because steps are added and moved. The same forms work on any list, whether its items are objects or plain values. The route has no list of plain values on this server, so the step
shows the list of objects. Where the order matters, read the list back: the notes of this repository say that `/rules/-` of a login restriction policy adds at the **start** (not tried here).

### Null and object (07)

`replace` with `null` clears a field that may be empty (`contact.email`). On a field that must have a value it is `400` (`disabled`).

An object is replaced **whole** by a `replace` on its path, and what the new object leaves out is reset:

```
--- replace a whole object with a fragment: what is left out is reset to null
  body:    [{"op":"replace","path":"/bandwidthLimits","value":{"policy":"custom","inboundLimit":100}}]
  before:  {"policy":"custom","inboundLimit":100,"outboundLimit":200}
  answer:  HTTP 204
  after:   {"policy":"custom","inboundLimit":100,"outboundLimit":null}
```

To change one field and keep the rest, `replace` the path of that field (`/bandwidthLimits/outboundLimit`). `remove` on the path of an object does not take it out of the answer: its fields are `null` and the object stays.

### Mistakes (08)

| Request | Answer | What is stored |
| ------- | ------ | -------------- |
| Two operations, the second on a field that is not there | `400` `Missing field "nosuchfield"` | Nothing: the first one is **not** applied. |
| `add` on `/contact/phon` (a typo) | `204` | Nothing. Read the object back. |
| `replace` on a field the object does not have | `400` `Missing field "nosuchfield"` | Nothing. |
| One operation, not in a list: `{"op":...}` | `400` `Incorrect JSON format` | Nothing. |
| An operation that does not exist: `swap` | `400` `unknown / unsupported operation swap` | Nothing. |
| No `Content-Type`, or `text/plain` | `415` `HTTP 415 Unsupported Media Type` | Nothing. |

Other refusals the Admin API gives (tried before on a throwaway account, not by a step here): `POST /accounts` with a body that has no valid `type` is `400` with a plain text, `Invalid discriminator value`; a name that is taken is
`409`; `limit=-1` is `400`; `fields=nonsense` is `400` `Field nonsense does not exist.`

### PUT (09 and 10)

PUT replaces the object. The safe way is the same every time: **read the object, change your copy, send the copy back.**

| What was sent | Answer | Result |
| ------------- | ------ | ------ |
| The object exactly as read, with one field changed | `204` | The change, and everything else as it was (step 09 compares the whole object). |
| The same, without `metadata` | `204` | The same. |
| The same, without the route's own `id`, with the `id` of each step | `400` `Cannot attach a route step to another route` | Nothing changed. |
| **A fragment:** `name`, `type`, `conditionType` and `description` | `204` | **The two steps are gone.** The server does not warn you. |
| The saved copy, after the fragment | `404` `Some Route steps are not found.` | The ids in it name steps that no longer exist. |
| A PATCH that replaces `/steps`, with the steps without `id`, `precedingStep` and `metadata` | `204` | The steps are back (with new ids). |

Never send a fragment. Every field you leave out is reset, and a `204` does not say so. (Tried on an account too: a fragment left the `user` object empty. Not tried here for sites, subscriptions, zones, transfer profiles and
user classes, where the same is reported.)

### A server setting (11)

An option is read and written at `/configurations/options`. The answer for one option, found with `?name=`, has `values` (a list of text), `defaultValues`, `readOnly` and `specified`. To change it, send a **list** of objects,
each with `name` and `values`, to PUT. The step changes `AddressBook.Limit.MaxDisplayEntries` from `100` to `77`, reads it, tries three requests the server refuses, and puts `100` back:

| What was sent | Answer |
| ------------- | ------ |
| `values` as a list of text: `["77"]` | `204`, the option is `["77"]` |
| `value` (one, not `values`) | `400` `Unsupported parameter - value` |
| One object, not a list of objects | `400` `Incorrect JSON format` |
| An option that does not exist | `404` `Configuration options with name(s) No.Such.Option not found` |

**Save the option before you change it, and compare after you put it back.** Save the whole answer, not only the value. The step keeps it in `state.local.option.json`, and refuses to start while that file is there (an earlier
run was stopped: run `99.cleanup_DELETE.sh`, which puts the option back from it).

## What to take from it

- **Read before you write, and read again after.** A `204` is not proof. Every case here prints the value before and after.
- **Write each value in its own type:** a text in quotes, a number and a boolean with none, a list as a list, an object as an object. The server converts some of the wrong forms in this release, and refuses others, and a patch
  that is accepted may store something else than you meant.
- **Look at the type of the field in the object you read**, not at what the value looks like (`uid` is text).
- **`remove` is not "make it empty".** It leaves `null`, or puts the default back.
- **A path into a list takes a position.** Find it in the object you just read.
- **PATCH only for fields you know are there. PUT only with the whole object as you read it.** Never a fragment.
- **Build every body with `jq` or a JSON library.** Text substitution breaks on a quote, a backslash or an ampersand. For an expression with `${ ... }` and backslashes, see
  [Expression Language in routes and sites](../../../Features/Guidance/expression-language-escaping.md).
- **The server checks the whole object**, not only your change. A `400` that names a field you did not touch means the stored object is already inconsistent: fix that field first.

## Tests

`tests/offline/checks/test_bash_admin_usecase_05.sh` runs every script against a stub `curl` and checks the call each one makes: the method, the URL, the exact body of every PATCH and PUT (a number is not quoted, a boolean is not
quoted, a list is addressed by position), the headers, its exit code and its messages, and that a case the server answers differently makes the step exit 1. `tests/online/checks/72.admin_usecase_changing_an_object.py` runs the whole
use case on a real server, tries every type again with its own calls and proves the stored value has the right JSON type, and proves that the option is back exactly and that nothing is left.
