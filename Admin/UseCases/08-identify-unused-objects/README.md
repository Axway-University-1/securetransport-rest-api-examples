# 08 Identify unused objects

**Use case:** an administrator wants to know which objects nothing uses: an application no subscription runs, a route template no composite route is made from, a route that nobody has run. To find them you need a **map of the relationships** between the objects, and the map has a **cost**: how many calls it takes
to read it. This use case builds a small set of objects, some with relations and some without, reads the map, and prints the objects that have no relation, **grouped by type**.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`Admin/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

**Checked on:** SecureTransport 5.5-20260924. Where the text says "tried", it was run on the lab, a test server of this version. A statement marked "not tried" was not run.

`00.run_all.sh` runs everything and ends with `99.cleanup_DELETE.sh` (about 35 seconds). It takes no parameter; the other scripts take their input as parameters and say what they need when it is wrong, before any call. Step 05 uses the End User API: set `ST_ENDUSER_PORT` in `set_variables.local.sh` when it is not the admin port minus one.
Step 01 needs `openssl` (it makes the key pairs of two certificates).

## The relationships

Who points to whom, with the field that holds the reference and the call that reads it:

| Object | Points to | Through | Read with |
| ------ | --------- | ------- | --------- |
| Certificate | its owner, an account | `account` | `GET /certificates` |
| Site | its owner, an account; a certificate | `account`; `clientCertificate` (the id) | `GET /sites` |
| Transfer profile | its owner, an account | `account` | `GET /transferProfiles` |
| Subscription | an account, an application, and for each transfer configuration a site and a transfer profile | `account`, `application`, `transferConfigurations[].site`, `.transferProfile` | `GET /subscriptions` (the list carries all of it) |
| Composite route | an account, a route template, subscriptions, and through its steps simple routes | `account`, `routeTemplate`, `subscriptions`, `steps[].executeRoute` | `GET /routes` |
| Route template | simple routes, through its steps (a template is a route too) | `steps[].executeRoute` | `GET /routes` |
| Simple route | sites, through a step that sends to a partner | `steps[].transferSiteExpression` (`SITE#!#CVD#!#`) | `GET /routes` |
| Application | nothing: it is used by subscriptions | | `GET /applications` |

Two things are not what you would guess. The **enabled or disabled** of a route is the `status` of the **step** that runs it (an `ExecuteRoute` step of a composite route or a template), not a field of the simple route. And a simple route can be run by **one** step only: a second step that names it is refused (400 "Route step's execute route cannot be referenced more that once as an execute route.").

## The rules

An object is **unused** when nothing points to it. The rules, as the script applies them (`unused.jq`):

| Type | Unused when |
| ---- | ----------- |
| Account | no site, no transfer profile, no subscription and no composite route has it as its account |
| Application (of type AdvancedRouting or Basic) | no subscription uses it. The maintenance applications (audit log, file purge, ...) are not judged: nothing is meant to use them |
| Certificate (private or local, with an owner) | no site names it. A trusted CA certificate has no owner and is never reported; a partner or login certificate is not judged either |
| Route template | no composite route is made from it |
| Composite route | no subscription starts it |
| Simple route | no step runs it; or only **disabled** steps run it **and** the server log does not name it (see "What the log says") |
| Site (not AS2, not PeSIT) | no subscription configuration and no route step names it |
| Subscription | no transfer configuration and no composite route is attached to it |
| Transfer profile (not a default one) | no subscription configuration of its owner names it |

A simple route that only disabled steps run, and that the log names, is **kept**: it ran in the past. The script lists it apart, so that you see it was looked at.

## The demo set

Step 01 to 04 make `example_unu_*` objects, so that the answer is known: **ten** objects that must come out as unused, and one that must be kept.

| | Used | Unused |
| - | ---- | ------ |
| Accounts | `a1`, which has everything below | `a2`, which has nothing |
| Certificates (private, owned by a1) | `cert_used`, named by `site_used` | `cert_unused` |
| Sites (ssh, a1) | `site_used` (a subscription), `site_step` (the step of `rt_orphan`) | `site_unused` |
| Transfer profiles (a1) | `profile_used` (a subscription) | `profile_unused` |
| Applications | `app_used` | `app_unused` |
| Subscriptions (a1) | `/example_unu_in`: `site_used`, `profile_used`, started by `comp_used` | `/example_unu_sub_unused`: nothing attached |
| Route templates | `tpl_used` | `tpl_unused` |
| Composite routes | `comp_used`: steps `rt_on` (enabled), `rt_old` (enabled, disabled in step 06) and `rt_never` (disabled) | `comp_unused`: no subscription |
| Simple routes | `rt_on` | `rt_never` (disabled, never ran), `rt_orphan` (no step runs it) |
| Kept | `rt_old`: disabled now, but it ran | |

That is 10 objects of 9 types: the right column, with `rt_never` and `rt_orphan` (simple routes) counted as two. A PeSIT site, `example_unu_pesit_support`, is made as well: the server refuses to make a transfer profile for an account that has no PeSIT site (400 "Account does not contain any PeSIT transfer sites."). It is never reported.

## The steps

| Script | What it does | Copied from |
| ------ | ------------ | ----------- |
| `01.accounts_certificates_POST` | Two accounts, and two certificates for `a1` (key pairs made by openssl, imported as PKCS#12 with usage private) | `05.Accounts/02.accounts_POST.sh`, `11.Certificates/03.certificates_POST_import_partner.sh` |
| `02.partnerships_POST` | Three sites, the PeSIT site, two transfer profiles | `06.TransferSites/02.sites_POST_ssh.sh`, `35.TransferProfiles/02.transferProfiles_POST.sh` |
| `03.subscriptions_POST` | Two applications, two subscriptions | `04.Applications`, `07.Subscriptions/02.subscriptions_POST.sh` |
| `04.routes_POST` | Two templates, four simple routes, two composite routes | `08.RouteTemplates`, `09.CompositeRoutes` |
| `05.upload_POST [SECONDS]` | `a1` uploads a file to its subscription folder: the composite route runs; the server log is read for each route | End User `FileOperations`, `28.ServerLogs/01.logs_server_GET.sh` |
| `06.step_PATCH_disable` | Disables the step that runs `rt_old` (PATCH by position) | `09.CompositeRoutes/10.routes_id_PATCH.sh` |
| `07.map_relationships_GET [PREFIX]` | **Part A.** Reads the map of the demo set and prints its cost | the GET lists |
| `08.server_log_search_GET [PREFIX]` | Searches the server log for each route that only disabled steps run | `28.ServerLogs/01.logs_server_GET.sh` |
| `09.unused_objects_GET [PREFIX]` | **Part B.** Prints the unused objects grouped by type, and compares them with the list that was built | |
| `10.whole_server_GET` | The same on the whole server, read only, with its cost | |
| `99.cleanup_DELETE` | Deletes everything by exact name; can be run twice | |

## What the log says about a route (the experiment of step 05)

A composite route runs its steps one after the other. The question was whether it skips a disabled step silently, or says so in the log, because the log is the only place that can tell whether a route that is disabled **now** was used in the past. Tried on 5.5-20260924, with the composite route `example_unu_comp_used` and one uploaded file:

- **The log names the composite route by name, and never the simple routes by name.** Every line of the run says `[example_unu_a1] [example_unu_comp_used]`. The simple routes that ran appear by **id**:
  `AR0011: [example_unu_a1] [example_unu_comp_used]  Sandbox environment {/home/example_unu_a1/.stfs/objects/…/<id of the simple route>} used for route execution` and `AR0108: … Step {Compress} with id {<id of the step of the simple route>} is starting.`
- **A route that a disabled step would have run leaves nothing.** No line names it, by name or by id, and no line says that a step was skipped. The log does not tell a skipped route. The only evidence that a route ran is a line with its id; no line is no evidence either way.
- **So the search is by id, not by name.** A search by the name finds the line "New route created" and the administrator's own requests, and tells nothing about use.
- **The search finds itself.** The server logs every request of the administrator, and the request holds the text that was asked for. Searching the log for an id finds the search for that id (`GET request for the following resource: /api/v2.0/logs/server?message=<id>…`), and the count grows by two with each search that is made. An entry that holds `/api/v2.0/` is the request and does not count. Without this rule, a route that never ran
  would be "found" by the very call that looked for it. (This is also why the answer can say `totalCount` 1 and `returnCount` 0: the count includes the entry of the request that is being answered.)
- The entries are in the log a second or two after the upload (3 s were measured).
- The search sees only the log the server has kept: a route last used before the oldest entry looks unused.

The result in the demo set: `rt_old` is found (1 entry), `rt_never` is not found (only the administrator's own requests). One call for each route that is disabled everywhere: that is part of the cost.

## The cost of the map

Each kind of object is read in pages of 100 (`limit` and `offset`, as in [use case 06](../06-lists-paging-and-fields/README.md)); the routes and the subscriptions are read whole, because `fields=` cannot name `subscriptions` on a route and the subscription list carries its transfer configurations. Measured on the lab (seconds are whole seconds):

| What was read | Demo set (prefix `example_unu_`) | Whole server |
| ------------- | -------------------------------- | ------------ |
| accounts, applications, sites, transfer profiles, routes | 1 call each | 1 call each |
| certificates | 1 call, 2 objects | 2 calls, 157 objects: the trusted CA certificates are read to find the few that have an owner (the slowest read: 3 to 4 s) |
| subscriptions | 2 calls, one for each account (`account=` is an exact match; a subscription has no name) | 1 call, 44 objects |
| **Total** | **8 calls, 22 objects, about 1 s** | **8 calls, 398 objects, 4 to 6 s** |
| The server log | 2 calls (one for each route that only disabled steps run) | 2 calls |

The number of calls grows with the number of objects, in pages of 100, plus one for each route that is disabled everywhere and one for each account when a prefix is used. The whole server on the lab has few objects; a server with thousands of sites and routes needs tens of calls, and the log search is the part that grows with the number of disabled routes. Run step 10 when the server is quiet.

With a **prefix**, the lists are filtered by name (`name=PREFIX*`), so only those objects are read. An object that does not match is not read, so a reference **from** it is not seen: an object of the prefix that something outside the prefix names would look unused. For a demo set that nothing else names, that is right; on a real server, use step 10.

## Reading the output

Step 09 prints the unused objects grouped by type, with the reason for each, a total, and the kept ones:

```text
Unused objects
  Account (1)
    example_unu_a2  (no site, transfer profile, subscription or composite route)
  Application (1)
    example_unu_app_unused  (no subscription uses it)
  …
  Route (2)
    example_unu_rt_never  (disabled in every step that runs it, and the server log does not name it)
    example_unu_rt_orphan  (no step of any route runs it)
  …
Total: 10 unused objects of 9 types.
Kept, although disabled now (1):
    example_unu_rt_old  (disabled now, but the server log names it: it ran in the past)
This is the list that was built on purpose: 10 objects, no more and no fewer.
```

On the lab, step 10 found 25 unused objects of 9 types: the 10 of the demo set, and real ones (accounts that nothing uses, applications and sites of earlier tests).

A reference counts **even when it comes from an unused object**. `site_step` is named by a step of `rt_orphan`, which nothing runs, and the site is "used" in this pass. Delete the orphan route, run the steps again, and the site shows up: finding unused objects is a loop, not one pass.

## What is not covered

- **AS2 and PeSIT sites.** They can be used only to receive a file (a partner connects to the server), so the configuration does not show that they are used. They are skipped, and so are the default transfer profiles (`default: true`) that PeSIT receiving uses without naming them. Only a search of the transfer log by site can tell, and it is not done here.
- Sites of types that name a certificate in another field (`clientLocalCertificate` and others): only `clientCertificate`, `loginCertificate` and `partnerCertificate` are read.
- Objects that are not in the list of the use case: user classes, zones, events, mail templates, login restriction policies, business units, administrators.
- A reference by expression: a site named through an expression (`transferSiteExpressionType` other than a list) or a template filled in at run time is not resolved.

## What to check before you delete

The list is a list of **candidates**, not a verdict.

- Is the object used in a way the configuration does not show: an AS2 or PeSIT partner, a script that names it by name, an event rule, an expression?
- Does the server log go back far enough? A route last used a year ago looks unused when the log keeps a month.
- Is the object new and not yet connected, or part of a set that is built in stages?
- Delete one object, run the steps again, and read the list again: what it pointed to may now be unused too.
