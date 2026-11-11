# Admin API 2.0 examples as JSON, for Swagger, Postman and Bruno

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer) before you run anything.

A complete example of one resource, the **accounts**, to show what such a folder would hold and to talk it over: 25 examples that
walk through the whole life of an account, from the first read to the delete. The same calls are in [bash/05.Accounts](../bash/05.Accounts/).
Nothing here goes into the objects an account has (certificates, sites, routes, subscriptions). Checked on release 5.5-20260924.

## What "JSON for Swagger" means

The Swagger UI of the server (`https://<server>:<port>/api/v2.0/docs/index.html`) is a form on top of the OpenAPI description.
Only one part of it takes JSON: **the body of a POST, PUT or PATCH**, typed into the *Request body* box under *Try it out*.
The parameters of a GET are not JSON: each goes into its own field. So, for Swagger:

| You want | What this folder gives | How you use it |
| -------- | ---------------------- | -------------- |
| A body to send | `swagger/<topic>/<example>.body.json` | Copy the file's content into the *Request body* box. |
| The parameters of a GET | `swagger/<topic>/<example>.parameters.json` | Type each value into the field of that name. Swagger has no import for them: the file is the list of values. |

The OpenAPI description of the server already has a list of ready bodies for `POST /accounts` (the *Examples* choice above the box:
UserAccount, TemplateAccount, ServiceAccount), but their values are the type placeholders `"string"` and `0`, so a send fails until
every field is edited. The bodies here are ones that were sent to a server and answered. To have them in that choice too, the
description would have to be served with them added, through a Swagger UI of your own, because the one on the server cannot be changed. That
is not done here.

## What "JSON for Postman and Bruno" means

Both are API clients that keep calls in a **collection**, and both fill in values from an **environment**. The collection holds
the method, the address with `{{variables}}`, the headers, the login, the body and a check of the status. The environment holds what
is yours: the host, the port, the account and its password. So the files are importable and carry no credential.

| | Postman | Bruno |
| - | ------- | ----- |
| What you import or open | `postman/ST-Admin-API-2.0.postman_collection.json` and `postman/lab.postman_environment.json`: two JSON files | the folder `bruno/`: it is the collection, plain text files (`.bru`), not JSON |
| Environment | `lab.postman_environment.json` | `bruno/environments/lab.bru` |
| Login | Basic, from `{{user}}` and `{{password}}`, set once on the collection | the same, in `collection.bru` |
| Check of the answer | a test on the status | an assertion on the status |
| Secrets | the two secret variables are empty, and of type *secret* | listed as `vars:secret`: Bruno keeps their values outside the files |

Bruno also imports a Postman collection, so the one JSON file would do for both. That was not tried here, and the `.bru` folder is
kept as well because it is what Bruno itself writes: a person who uses Bruno and git gets one small file for each call, and a
change shows as a line.

## The structure, and why it is built from one source

```
Admin/API 2.0/json/
  README.md
  examples/                          the one source: one small JSON file for each example, named like the bash example
    05.Accounts/
      01.accounts_GET.json ... 07.accounts_name_DELETE_user.json     (25 files)
  swagger/                           made from it: to paste, or to type in
    05.Accounts/
      <example>.body.json            for each example with a body
      <example>.parameters.json      for each example with a path parameter or a query
  postman/                           made from it: import both files
    ST-Admin-API-2.0.postman_collection.json
    lab.postman_environment.json
  bruno/                             made from it: open this folder in Bruno
    bruno.json, collection.bru
    environments/lab.bru
    05.Accounts/ folder.bru, one .bru file for each example
```

The topic folder and the numbers are those of `bash/`, and a letter or number after the method tells the variants apart (`02.accounts_POST_user`, `06.accounts_name_PATCH_4_add_contact`). Only `examples/` is
written by hand: the rest is made by `python3 tools/build_json_examples.py`, and the offline test fails when a file differs from what the
source gives. With the whole API (hundreds of calls) three hand-kept copies would drift apart; the test is what stops it. A body is
written once in `examples/`, and a Bruno file, which cannot refer to another file for its body, gets its own copy of it.

## The 25 examples

In the order they run. Each sends one request and the collections check the status, so an error that is answered on purpose (409, 400, 404) is
a pass. The first column is the file name in `examples/`; the last is its title in Postman and Bruno.

| Example | Call | Answers | What it shows |
| ------- | ---- | ------- | ------------- |
| `01.accounts_GET` | `GET /accounts?type=user&fields=name,homeFolder&limit=5` | 200 | Get accounts |
| `01.accounts_GET_by_name` | `GET /accounts?name=example_*&type=user&fields=name` | 200 | Get accounts by name |
| `01.accounts_GET_by_status` | `GET /accounts?status=DISABLED&type=user&fields=name&limit=5` | 200 | Get accounts by status |
| `01.accounts_GET_page` | `GET /accounts?type=user&fields=name&limit=2&offset=2` | 200 | Get the second page of accounts |
| `02.accounts_POST_service` | `POST /accounts` | 201 | Create a service account |
| `02.accounts_POST_template` | `POST /accounts` | 201 | Create a template account |
| `02.accounts_POST_user` | `POST /accounts` | 201 | Create a user account |
| `02.accounts_POST_user_duplicate` | `POST /accounts` | 409 | Create a user account that exists |
| `03.accounts_name_HEAD` | `HEAD /accounts/{name} (name = example_user)` | 200 | Check that an account exists |
| `03.accounts_name_HEAD_missing` | `HEAD /accounts/{name} (name = example_missing)` | 404 | Check an account that does not exist |
| `04.accounts_name_GET` | `GET /accounts/{name} (name = example_user)` | 200 | Get one account |
| `04.accounts_name_GET_addressBookSettings` | `GET /accounts/{name}?type=user&fields=addressBookSettings (name = example_user)` | 200 | Get a field of one account type |
| `04.accounts_name_GET_fields` | `GET /accounts/{name}?fields=name,homeFolder,uid (name = example_user)` | 200 | Get fields of one account |
| `04.accounts_name_GET_fields_without_type` | `GET /accounts/{name}?fields=addressBookSettings (name = example_user)` | 400 | Get a field of one account type, without the type |
| `05.accounts_name_PUT_service` | `PUT /accounts/{name} (name = example_service)` | 204 | Replace a service account |
| `05.accounts_name_PUT_user` | `PUT /accounts/{name} (name = example_user)` | 204 | Replace a user account |
| `06.accounts_name_PATCH_1_replace_policy` | `PATCH /accounts/{name} (name = example_user)` | 204 | Patch: replace one field |
| `06.accounts_name_PATCH_2_replace_two` | `PATCH /accounts/{name} (name = example_user)` | 204 | Patch: replace two fields |
| `06.accounts_name_PATCH_3_remove` | `PATCH /accounts/{name} (name = example_user)` | 204 | Patch: remove a field |
| `06.accounts_name_PATCH_4_add_contact` | `PATCH /accounts/{name} (name = example_user)` | 204 | Patch: add to an array |
| `06.accounts_name_PATCH_5_remove_contact` | `PATCH /accounts/{name} (name = example_user)` | 204 | Patch: remove an array element |
| `06.accounts_name_PATCH_6_notes` | `PATCH /accounts/{name} (name = example_user)` | 204 | Patch: add a field |
| `07.accounts_name_DELETE_service` | `DELETE /accounts/{name} (name = example_service)` | 204 | Delete the service account |
| `07.accounts_name_DELETE_template` | `DELETE /accounts/{name} (name = example_template)` | 204 | Delete the template account |
| `07.accounts_name_DELETE_user` | `DELETE /accounts/{name} (name = example_user)` | 204 | Delete the user account |

- **Run top to bottom.** The collection is a story: the three accounts are created, read, changed and deleted, and what an example needs is made by an earlier one
  (`02.accounts_POST_user_duplicate` needs the user, the patches need the PUT's password). Run alone, an example may answer 404. At the end no account is left.
- **The names are fixed**: `example_user`, `example_service`, `example_template`, as in the bash examples, which also delete them. An account of one of
  those names that is already on the server makes the creates answer 409.
- **A PUT needs the password.** It replaces the whole object and the server never returns the password, so the body carries it. A field left out is reset.
  The bash example reads the object and sends it back with one change; a collection cannot do that without a script, so the body here is written out.
- **A PATCH is a list of operations** (`add`, `replace`, `remove`), also for one change. `-` as the last part of a path adds to the end of an array.

## Using them

**Swagger.** Open the Swagger UI, choose *Authorize*, and enter an administrator and its password. Open `POST /accounts`, *Try it
out*, paste `swagger/05.Accounts/02.accounts_POST_user.body.json`, and **change the password in it first**. Choose *Execute*.

**Postman.** *Import* both files of `postman/`. Choose the environment *ST lab*, and fill in `server`, `port`, `user`, `password` and
`accountPassword` (the password of the new account). Run the folder, or one request.

**Bruno.** *Open Collection*, choose `bruno/`, choose the environment *lab* and fill in the same five values. Run the folder, or
one request. From the command line, in that folder: `bru run --env lab --env-var password=... --env-var accountPassword=... --insecure`.

## Things to know

- **The placeholder password is accepted.** The server accepts any password, `REPLACE_WITH_A_PASSWORD` too: pasted unchanged, the body
  creates `example_user` with a password that anyone who reads this file knows. Replace it before you send, and delete the account
  afterwards with [bash/05.Accounts/07.accounts_name_DELETE.sh](../bash/05.Accounts/07.accounts_name_DELETE.sh).
- **Sending it twice answers 409**: the account name is not unique. A successful create answers 201 with no body; the address of the new
  account is in the `Location` header.
- **The `Referer` header.** The bash examples send one, so both collections do (a browser sends it by itself, which is why Swagger needs none).
- **A lab server has a certificate of its own.** Postman: *Settings, SSL certificate verification* off. Bruno: *Preferences, SSL/TLS
  certificate verification* off, or `--insecure` on the command line. Do that for a lab only.
- **The address is `https://{{server}}:{{port}}/api/v2.0`**, and the port is the admin one: see [Which port?](../../../README.md#which-port).

## Left out on purpose

| What | Why |
| ---- | --- |
| `06.accounts_name_PATCH_secretQuestion.sh` | It makes the account unusable until its user chooses a new secret question, and it needs the service switched on. Not one for a collection that is run in a row. |
| `06.accounts_name_PATCH_with_file.sh`, and the business unit sample | The point of that script is to read the body from a file; in a collection the body is in the request. The business unit sample names a unit that only one server has. |
| Certificates, sites, routes, subscriptions of an account | The objects under an account are their own resources. |
| `18.AccountSetup` | Another resource, though it creates accounts. |

## How it was checked

On a 5.5-20260924 lab: both collections were run in full with their own command line tools, newman 6.2.3 for Postman and the Bruno CLI 4.3.0:
25 requests, every one the status it names, and no account left. The same 25 are replayed by the online check
`tests/online/checks/80.admin_json_examples_accounts.py`, which also reads the accounts back to see that the PUT and the patches did what they say, and sends the
Swagger body with its placeholder (201). **Not done:** the Postman and Bruno applications were not opened (the command line tools read the same files), and the Swagger UI was not opened
in a browser. The offline test (`tests/offline/checks/test_json_examples.py`) checks the files against the source, the bash example and the rules above.

## Questions for the review

1. **Which tools?** Swagger, Postman and Bruno are all here. Is one of them enough, or is a fourth wanted (Insomnia, Hoppscotch, `.http` files for VS Code)?
2. **One source or the bash headers?** `examples/` is written by hand and a test ties it to the bash example. Should it be generated from the bash headers instead, so there is one thing to keep?
3. **Errors on purpose.** Three examples answer 409, 400 and 404 to teach the error. Do they belong in the run, or in a folder of their own?
4. **Run top to bottom, or each alone?** A collection that is a story shows the life of an object, but cannot be run in part. The other way: each example makes what it needs and cleans up.
5. **Reading and sending back.** The bash PUT reads the object and sends it back with one change. The collections could do the same with a script that keeps the answer in a variable (Postman and Bruno both can). That teaches more and is harder to copy.
6. **Variables.** Six: the host, the port, the account, the user class, the two passwords. Too few, too many, other names?
7. **The login.** Basic, as in the bash examples. The reference also offers an administrator API key (`SECURETRANSPORT-API-KEY`), which was not tried here.
8. **The Swagger side.** Bodies to paste, and values to type for a GET. Is a Swagger UI of our own, with the bodies in its *Examples* list, worth building?
9. **The names.** The folder is `json`; the files are named like the bash ones with a number after the method for a series. Better ideas?
10. **Upkeep.** Each new resource or release adds source files and a test. Who checks that the Features folder and these stay in step with the API?

