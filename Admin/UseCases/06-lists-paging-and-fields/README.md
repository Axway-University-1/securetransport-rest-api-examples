# 06 Lists, paging and fields

**Use case:** read a list from the Admin API the way a program must: know what one answer holds, walk a long list page by page, ask for fewer fields, ask whether one object exists, read the address of a new object, and filter.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`Admin/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

Steps 01 to 04 only read. They run on `accounts` unless you name another list, and none of them changes anything. Step 05 makes five throwaway business units named `example_lst_1` to `example_lst_5` (a business unit needs only a
name and a base folder, and makes no folder on the server), step 06 reads them with a filter, and `99.cleanup_DELETE.sh` removes them by name. End users have the same lists with other rules: see
[08 Lists and paging](../../../EndUser/UseCases/08-lists-and-paging) in the End User use cases.

## The examples

Run them in order (`00.run_all.sh [RESOURCE] [PAGE_SIZE]` runs them all and ends with `99.cleanup_DELETE.sh`). The scripts take their input as parameters, and say what they need when it is wrong, before any call.

| Script | What it does | Copied from |
| ------ | ------------ | ----------- |
| `01.list_default_GET [RESOURCE]` | What a list answers when you ask for nothing more: `returnCount`, `totalCount`, the page size the server uses, and what `limit=0` and `limit=1` do. | `Admin/API 2.0/bash/05.Accounts/01.accounts_GET.sh` |
| `02.paging_walk [RESOURCE] [PAGE_SIZE]` | Reads the whole list, page after page, stops at `totalCount`, asks for a page past the end, and checks the sum. | |
| `03.fields_GET [RESOURCE] [FIELDS]` | `fields=` narrows each entry; a field that does not exist is 400; `protocol` on `/servers` is in every answer and cannot be asked for. | `05.Accounts/01.accounts_GET.sh` |
| `04.head_exists [RESOURCE] [NAME]` | `HEAD`: 200 it is there, 404 it is not, and 405 for a resource that has no `HEAD`. | `05.Accounts/03.accounts_name_HEAD.sh` |
| `05.location_POST [COUNT]` | Makes COUNT business units, shows the `Location` header of each, reads the first back by it, and shows what a second POST of a name answers. | `12.BusinessUnits/01.businessUnits_POST.sh` |
| `06.filters_GET [PAGE_SIZE]` | A filter (`name=example_lst_*`) with `limit`, `offset` and `fields=`: what `totalCount` counts, a filter that finds nothing, capitals. | `12.BusinessUnits/02.businessUnits_GET.sh` |
| `99.cleanup_DELETE` | Removes `example_lst_1` to `example_lst_9` by name, the state files and the administrator's session. Can be run twice. | |

```
./01.list_default_GET.sh logs/transfers     # a list longer than a page: returnCount 100, totalCount in the thousands
./02.paging_walk.sh servers 2               # two entries a call
./03.fields_GET.sh accounts name,contact.email
./04.head_exists.sh accounts john
```

`lib.sh` is the shared file: it loads `../session.sh` (the settings, the Admin session in `session.cookie.jar`, which git ignores) and has the checks of the parameters and the one call that every read makes.

## What to take from it

**The answer of a list.** An Admin list is `{"resultSet": {"returnCount": 5, "totalCount": 19}, "result": [...]}`. `totalCount` is the number of entries that match your filter, in all. `returnCount` is the number in this answer, and
it never passes `limit`. To count, read `totalCount`; to only count, ask for `limit=1`.

**A page is 100 entries when you do not ask for more.** That is the setting `Webservices.EntriesPerPage`, and step 01 reads it. `limit=0` gives the same 100: it does not mean "all". On the lab's transfer log (23,368 entries, so more than a page):

| You ask for | You get |
| ----------- | ------- |
| no `limit` | 100 |
| `limit=0` | 100 |
| `limit=1000` | 1000, in about 4 seconds |
| `limit=5000` | 5000, in about 15 seconds (timed earlier: the online check does not repeat it) |

A client with a 30 second timeout can fail on a big page when the server is busy: ask for a few hundred and walk the pages, as 02 does. A `limit` that is not a number is 400 `'limit' param is not a number`, and below 0 it is
400 `The limit should be a positive number or 0.`

**Walk with `limit` and `offset`.** `offset` is the number of entries to skip. 02 asks for a page, adds what it got to the offset, and stops when it has read `totalCount` entries. A page past the end is not an error: 200, an empty `result`,
and the same `totalCount`. If the list changes while you read it (an entry is added or removed), the pages move: sort when the resource has a sort parameter (the transfer log has `sortByStartTime`), and compare what you read with `totalCount`.

```python
def all_entries(get, path, params=None, page=500):
    """Every entry of an Admin list. get(path, params) returns the decoded answer of one call."""
    entries, offset = [], 0
    while True:
        answer = get(path, dict(params or {}, limit=page, offset=offset))
        got = answer["result"]
        entries.extend(got)
        if len(got) < page:                     # a short page is the last one
            return entries
        offset += page
```

**`fields=` narrows the answer.** `fields=name` gives each entry its `name` and the `type` of the object. A name inside an object is written with a dot (`contact.email`); the name of the object (`contact`) gives all of it. A field that does not
exist is 400 `Field nosuch does not exist.`. And there is one that you cannot ask for: `fields=protocol` on `/servers` is refused with that same message, although every server in the answer has a `protocol` (and `fields=type` on `/sites` is refused too).
The field that tells the kind of an object is always there: leave it out of `fields=` and read it from the answer. A client that asks for fields and gets a 400 should ask again without `fields=` and pick what it needs.

**`HEAD` is the cheap question.** No body, and the code is the answer: 200 it is there, 404 it is not. Not every resource has one: `deniedUsers` answers 405 to a `HEAD` of one name (and to a `GET` of it), because it has no
read of a single object. Look at the code, and do not take a 405 for "not there".

**The `Location` header.** A `POST` that creates answers 201 with **no body**; the address of the new object is in the `Location` header. Ask curl for the headers with `-D file`. For a business unit and an account the last part of the address is
the name; for other objects, a route for one, it is an id. Read the address from the header and do not build it. A name that is taken is refused and nothing changes (for a business unit it is 400, for an account 409: read the message).

**Filters change `totalCount`.** A filter counts what matches, not what the resource holds: 5 of 6 for `name=example_lst_*`, and 0 of 0 for a pattern that matches nothing, which is an empty list and not an error. The `name` filter of a business unit takes `*`
and does not care about upper and lower case. Earlier work on other resources found a few where the total ignores the filter, and one where a filter is ignored (the zones). Check the resource you use.

**Two answers that are not an Admin list.** A daemon operation answers a bare list, and `/myself` an object: step 01 says so when the answer has no `resultSet`. The End User API has plain arrays and an object with no count
([08 Lists and paging](../../../EndUser/UseCases/08-lists-and-paging)).

## Tests

`tests/offline/checks/test_bash_admin_usecase_06.sh` runs every script against a stub `curl` and checks the call each one makes (the query it builds, the body of a POST, the headers), the pages a walk asks for, its messages and exit codes.
`tests/online/checks/73.admin_usecase_lists_paging_and_fields.py` runs the whole use case on a real server, reads what it made through its own session, and proves that nothing is left.
