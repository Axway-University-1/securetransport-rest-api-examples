# Integration tests

These talk to a **real SecureTransport**. The checks in `tests/checks` prove the
examples are internally consistent; these prove the server still behaves the way
the examples assume.

The harness itself (`st_client.py`) is standard library only — no `pip install`
needed to run the checks against the bash and bat examples.

```
tests/integration/run_integration.sh            read only
tests/integration/run_integration.sh --write    also create and delete an account
tests/integration/run_integration.sh --mock     against the bundled mock, no server
```

Checks `15` through `18` run the real Admin API 2.0 **python3** examples,
which import `requests` (and one, `requests_toolbelt`) - third-party
libraries the harness itself deliberately does not depend on. Those checks
need a one-time venv, gitignored under `tests/local/`:

```
python3 -m venv tests/local/pyvenv
tests/local/pyvenv/bin/pip install requests requests_toolbelt
```

Without it, checks `15`-`18` and `20` report a clean skip rather than fail
(`19` is bash only and does not need it).

## Try it with no server first

```
tests/integration/run_integration.sh --mock --write
```

That starts a small stand-in SecureTransport on localhost over real HTTPS and
runs the same checks against it. It proves the harness works — the CSRF
handshake, the Referer requirement, paging, the status codes — so that when you
point it at a real server, a failure is a real difference and not a bug in the
tests.

The mock is not a SecureTransport simulator and does not try to be.

**`04.accounts_scripts.py` will fail against `--mock`, on purpose.** It runs
the real `Admin/API 2.0/bash/05.Accounts` scripts, and none of them send a
`Referer` header — the mock enforces it, matching the documented contract,
where the real lab this was validated against does not. That gap is itself a
real, confirmed finding (see the gotchas skill), not a mock bug — run this
particular check against a real server rather than `--mock` to see it pass.

## Pointing it at your own server

```
mkdir -p tests/local
cp tests/integration/integration.conf.example tests/local/integration.conf
$EDITOR tests/local/integration.conf
```

`tests/local/` is gitignored, so the address and credentials never reach the
repository.

## Safety

Four gates, in order:

1. **No config, no run.** Without `tests/local/integration.conf` the suite
   reports a skip and exits 0, so a clean clone is not a failure.
2. **`st_confirm_lab="yes"`** must be in the config. It is a deliberate
   statement that the server is not production. Nothing runs without it.
3. **Writing needs two separate yeses:** `--write` on the command line *and*
   `st_allow_writes="yes"` in the config. With either missing, the read only
   checks still run and the lifecycle check skips.
4. **Everything created carries `st_object_prefix`**, default `ZZTEST_`. The
   lifecycle check refuses to delete anything without it, and tears down what it
   made even when an assertion fails. If teardown cannot complete it says so, by
   name, so you can remove the object by hand.

Read only means read only: checks 01 and 02 issue nothing but GET and HEAD.

## What each check covers

`01` to `03` prove the API behaves the way the examples assume, using a small
client written for this harness (`st_client.py`). `04` is a different kind of
check: it runs the actual, unmodified script files that ship in
`Admin/API 2.0/bash`, so a bug in the real curl invocation — bad quoting, a
stale field name, a broken `jq` filter — is what it catches, not just a wrong
assumption about the API.

| Check | Writes? | What it proves |
| ----- | ------- | -------------- |
| `01.connect.py` | no | Login, the CSRF handshake, `/myself`, `/version`, logout. Also whether your server really does reject a call with no `Referer`. Run this first: if it fails, nothing else will work and the reason is here. |
| `02.read.py` | no | The behaviours every example depends on: the `result` and `resultSet.returnCount` envelope, paging that does not overlap or repeat, `fields=` narrowing the response while `type` still comes back, HEAD as an existence check, 404 for a missing object, and that a type specific field needs `type=`. |
| `03.lifecycle.py` | **yes** | The full cycle on one account, through a harness-written client: POST returning 201 with a `Location` header, GET and HEAD, PATCH returning 204, `replace` on an unset field being rejected, PUT replacing the object while preserving other fields, the object appearing in the collection, and DELETE really removing it. |
| `04.accounts_scripts.py` | **yes** | The same cycle, but by running the real `01` through `07` scripts in `Admin/API 2.0/bash/05.Accounts` and verifying each step independently through the API. Touches the literal accounts those scripts create (`UserAccount`, `ServiceAccount`, `TemplateAccount`), not a `ZZTEST_` prefixed name — see its own docstring for the safety rules around that, and around the `john` account two of the scripts depend on. If `john` already exists, `06` and its `_with_file` twin run as name-substituted copies against a throwaway `john_test` instead of being skipped — see "Substituted-copy fallbacks" below. |
| `05.applications_scripts.py` | **yes** | The real `02` through `07` scripts in `Admin/API 2.0/bash/04.Applications`. If this server already has an application of type `AccountFilePurge` under any name - only one is allowed per server, confirmed directly, and this is exactly the gap that had left `07...DELETE.sh` cleaning up the wrong objects until it was fixed (see the gotchas skill) - `04` through `06` run as name-substituted copies targeting `HumanSystem Application` instead of skipping the whole check. |
| `06.servers_scripts.py` | **yes** | The real `07` through `12` scripts in `Admin/API 2.0/bash/03.Connect` - server create, read, update, delete. Deliberately not `01`-`05` or `13`: those read or change a daemon (a singleton, not a disposable object) or start and stop real daemons and servers. |
| `07.businessunits_scripts.py` | **yes** | The real `01.businessUnits_POST.sh`, verified and cleaned up through the API (`38` runs the folder's other examples). If a business unit named `Finance` already exists, this runs a name-substituted copy targeting a throwaway `Finance_test` instead of skipping. |
| `08.transfersites_scripts.py` | **yes** | The real `01.sites_POST.sh`, the same way as business units. A site is addressed by a generated `id`, not by name - confirmed directly, and found via `GET /sites?name=...`. If a site named `HTTP` on account `john` already exists, this runs a name-substituted copy targeting `HTTP_test` on the same, unmodified `john` account instead of skipping. |
| `09.connect_read.py` | no | `01.daemons_GET.sh`, `02.daemons_name_GET.sh` and `06.servers_GET.sh` for real, plus that every daemon status is one of the two documented values. The read-only counterpart to what `06.servers_scripts.py` deliberately excludes. |
| `10.configurations_read.py` | no | The shape of a Server Configuration Option response, and that a made up option returns 404. Deliberately never runs either PATCH script in `13.Configurations` - a Configuration Option is a real, persistent server setting, not a disposable object. |
| `11.enduser_scripts.py` | **yes** | The full `EndUser/API 2.0/bash` cycle for real: login, list, upload, download, bulk upload and download, logout. Needs no separate end user account configured ahead of time - it creates its own throwaway one through the admin API and deletes it afterward, the same pattern `04.accounts_scripts.py` uses for `john`. Found and fixed a real bug in the process: both download scripts were writing the HTTP status code onto the end of every downloaded file. |
| `12.myself_and_version_scripts.py` | no | The real scripts in `Admin/API 2.0/bash/01.Authentication` and `02.Introduction`: login with and without a cookie jar, `/version`, `/myself`, and logout. No object is created, so this needs no `--write`. Verifies session reuse and logout independently by reusing the cookie jar a script wrote, in a fresh request the script itself never checks the result of. Deliberately excludes `02.Introduction/04.myself_PATCH.sh`, covered separately below. |
| `13.myself_patch_scripts.py` | **yes** | The real `02.Introduction/04.myself_PATCH.sh` - the one script `12` excludes, because it changes the currently authenticated user's own password. Run instead against a throwaway administrator this check creates through `/administrators` (a different resource from `/accounts`, confirmed directly) and deletes afterward - the real file runs completely unmodified, since it is not parameterised by account name at all. |
| `14.daemon_write_scripts.py` | **yes** | The real `03.daemons_name_PUT.sh` and `04.daemons_name_PATCH.sh` against the one daemon `/daemons/{name}` will ever address - `ssh` - since no other name is valid regardless of what exists on the server. Reads the daemon's real settings first, runs both scripts, verifies each change, then restores the original settings and verifies the restore. See "What is not covered yet" for the reasoning; this needed an explicit, informed decision before it was added. |
| `15.python_read_scripts.py` | no | The real `stGetAccountsAfterDate.py` and `stConfigScan.py` (both modes) from `Admin/API 2.0/python/python3`. No object is created, so this needs no `--write`, just the venv above. `stConfigScan.py` runs as a name-substituted copy, retargeting its hardcoded `/home/axway/stConfig.baseline` at `tests/local` - that path only exists on a real ST host. |
| `16.python_build_delete_accounts.py` | **yes** | The real `stDeleteTestAccounts.py`, and a count-and-name-substituted copy of `stBuildTestAccounts.py` (3 accounts and 1 process instead of 100 and 3, and its unconditional business unit renamed to a throwaway `ZZTEST_` name) - the pairing the scripts' own naming convention (`ZZ` + index, matched by `stDeleteTestAccounts.py`'s hardcoded substring filter) already anticipates. |
| `17.python_login_restriction.py` | **yes** | The real, completely unmodified `stAddLoginRestrictionRule.py`, against a throwaway login restriction policy this check creates and deletes - the script takes the policy name as a real argument, so no substitution is needed at all. |
| `18.python_replace_sites.py` | **yes** | The real, completely unmodified `stReplaceSites.py`, against every real SSH-protocol site on the server - there is no disposable stand-in, since the script has no name or prefix filter at all. Reads every site's full object first, runs the script, verifies each site's `keyExchangeAlgorithms`, then restores every site to its original object and verifies the restore, including that each site's already-encrypted password field survives unchanged. This needed an explicit, informed decision before it was added - this server had real-looking partner sites in scope. See "What is not covered yet". |
| `19.bash_expression_language.py` | **yes** | The real, unmodified Expression Language exercises in `Admin/API 2.0/bash/14.ExpressionLanguage` (8 scripts) - a login restriction rule, an EL route condition, a route step's GLOB and REGEXP file filters, the nested EL-plus-JSON backslash doubling case, a rename expression, and a transfer site's `downloadPattern` and dynamic-property fields. Each script is self-contained (creates, shows, deletes its own throwaway objects); this check verifies each script's own printed output shows the exact expression text expected, then independently confirms nothing named `ZZTEST_EL_*` is left in routes, sites or loginRestrictionPolicies. |
| `20.python_expression_language.py` | **yes** | The same eight exercises, run through their python3 twins in `Admin/API 2.0/python/python3/14.ExpressionLanguage`. Same verification approach as `19`. |
| `21.configurations_write_scripts.py` | **yes** | The real `01.configurations_PATCH.sh` and `02.configurations_PATCH_UsageReporting.sh` in `13.Configurations`. A Server Configuration Option is a real, server-wide setting, so this reads every option's value first, runs both scripts, verifies each new value, then restores every option and verifies the restore. Found that an option GET reports as `readOnly` can still be patched. |
| `22.routetemplates_compositeroutes_scripts.py` | **yes** | `08.RouteTemplates/02.routes_POST.sh`, trimmed from its 163 template names to 3 (keeping `RouteFromAccountant`, which the next script needs), then the real, unmodified `09.CompositeRoutes/02.routes_POST.sh`. Refuses to run if any of the names it creates already exist, and deletes every route it made. |
| `23.connect_operations_scripts.py` | **yes** | The real `05.daemons_operations_POST.sh` and `13.servers_operations_POST.sh` in `03.Connect`, which stop and start real daemons and servers. Records every daemon and server state first, runs both, verifies the stop and the start, then restores AS2 to stopped and waits for every daemon and server to match its original state. `13` only starts what is not running, so on its own it is a safe no-op. Needed an explicit decision before it was added. |
| `24.python_read_reports.py` | no | The real `stUsersPerSharedFolder.py` and `stCertificateExpiry.py`. Both only read, so this needs no `--write`, just the venv above. Each count they report is checked against an independent GET. |
| `25.python_update_route_with_put.py` | **yes** | The real `stUpdateRouteWithPut.py` in its default `insert` mode, on a throwaway route it creates: reads the route, inserts a step at offset 0, PUTs the whole object back. Runs as a copy with `dryRun` off; verifies the step landed, then deletes the route. |
| `26.python_get_private_cert.py` | **yes** | The real `stGetPrivateCert.py`, exporting a private certificate this check generates for a throwaway account through `POST /certificates`. Needs this server's CA password in `st_ca_password`, and skips itself when that is blank. Verifies a real private key was exported, then removes the certificate, the account and the files written. |
| `27.python_update_all_routes.py` | **yes** | The real `stUpdateAllRoutes.py` (its first example) over every SIMPLE route on the server, plus a throwaway one built to match its condition. Verifies only the throwaway route is patched and the real ones are left alone - confirmed beforehand that no real route matches. |
| `28.python_build_full_test_account.py` | **yes** | The real `stBuildFullTestAccount.py` end to end: account, an imported SSH key, a folder-monitor site, an SFTP site using that key, a subscription and two routes. Creates `ZZTEST_` stand-ins for the template and application the script expects, generates the key with `ssh-keygen`, and needs `st_ca_password`. Verifies all seven objects, then deletes them. Found and fixed two hardcoded account names in the script. |
| `29.python_update_all_subscriptions.py` | **yes** | The real `stUpdateAllSubscriptions.py` over every real subscription on the server - the one check approved to change objects it does not own. Captures the four fields it patches on every subscription first, runs the script, then restores each field to its exact original value and verifies the restore. |
| `30.lookups_and_transfer_logs_read.py` | no | The query filters the newer examples look objects up with - `/sites?account=&name=`, `/subscriptions?account=`, `/routes?type=` and `?name=`, `/logs/transfers?status=Failed` - each checked against every object it returns, using objects already on the server. That `/logs/transfers` carries `totalCount` while `returnCount` is capped by `limit`. Then the real `16.TransferLogs` scripts and `stBillableTransfers.py` (with the venv), each printed count compared with the API's own count for the same account and day. The billable parts need 5.5-20260924 or later. |
| `31.subscriptions_routes_transfers_scripts.py` | **yes** | The newer examples as one Advanced Routing flow, on a throwaway `ZZTEST_chain` account: the EndUser folder and upload scripts, the SSH sites, both subscriptions, the Compress and Decompress routes, the composite route linked to the subscription, a pull, the transfer log, and then the clean-up examples in reverse. Each step is checked through the API, and the flow is proved end to end by the uploaded file arriving, pulled, compressed and pushed, in the account's `/delivered` folder. The Admin examples run as name-substituted copies (`john` and every fixed name made throwaway, which `test_integration_helpers.py` checks offline); the EndUser examples run unmodified. The trigger-file subscription and the billable count need 5.5-20260924 or later. Set `st_ssh_host`, `st_ssh_port` and `st_enduser_port` if the defaults do not fit your server. |
| `32.pesit_acknowledgment_loop_scripts.py` | **yes** | A PeSIT loop between two throwaway accounts on the one server (each with a PeSIT site named after the other, and a transfer profile), and the real `Acknowledgment.sh` and `IteratePesitInbounds.sh` run on the transfers it makes: a NACK for a file nothing forwards, an ACK for one a subscription and route push on under the same `coreId`, and the iterator ACKing the forwarded one while leaving the other for later. The iterator acts on every unacknowledged PeSIT inbound on the server in its window, so it only runs when all of them belong to throwaway accounts. Set `st_pesit_host` and `st_pesit_port` if your PeSIT listener is not `st_server`:17617. |
| `33.enduser_api_scripts.py` | **yes** | The EndUser examples added from the API reference, run as a throwaway end user with a throwaway partner: the account, a password change and back, the secret questions (or a clean "service not enabled"), the address book; an upload with `Content-MD5`, metadata, listing parameters, rename by PUT and PATCH, share and unshare; MD5Calc, a chunked and a multipart upload, a cancel; a pull and its summary, a push and a folder monitor run through SSH sites the admin API gives the user; the transfer log; the server time. Each effect is checked through the API. Not run: the password reset pair (needs a real email) and `verifymdn` (needs AS2). Puts back your own `myCookie.jar` and `set_variables.local.sh`. |
| `34.access_policies_scripts.py` | **yes** | The real `17.AccessPolicies` examples: adds a `reject` rule for a database and user that do not exist, after the server's own rules; checks, reads and replaces it, adds a second copy, deletes both, and checks the server's rules are exactly as they were. Rule ids are positions that move up after a delete, so the delete example re-lists before each one. Only for a server on the embedded PostgreSQL database. |
| `35.account_setup_scripts.py` | **yes** | The real `18.AccountSetup` examples on a throwaway `example_setup` account: the account and an SSH site in one call, a second site added to the existing account (which is skipped, not refused), the whole setup read back, and the delete, checked to take the sites with it. |
| `36.address_book_scripts.py` | **yes** | The real `19.AddressBook` examples on the server's LDAP source, which has no POST or DELETE: changes its page size with PATCH and back with PUT, and checks the source is exactly as it was. Skips when there is no LDAP source. |
| `37.administrators_scripts.py` | **yes** | The real `20.AdministrativeRoles` and `21.Administrators` examples: a throwaway role and an administrator that holds it; read, lock, unlock, replace and patch; an API key, a call made with the key alone, its revoke and the 401 that follows; deleting the role with its administrator moved to another role. Also lists your own administrator under your own role, a name with a space. |
| `38.business_units_scripts.py` | **yes** | The real `12.BusinessUnits` examples 02 to 07 on a throwaway unit and a nested one whose name has a space, with one account in it: list, check, read and count the account, PUT and PATCH, the delete refused while a nested unit or an account remains, then the deletes. |
| `39.certificates_scripts.py` | **yes** | The real `11.Certificates` examples: generates `example_cert` with the server's CA, checks the 40 and 20 day expiry searches, reads and patches it, exports it as pem, crt and pkcs12, imports the pem as a throwaway account's partner certificate; then a signing request generated, listed and read, signed by a throwaway CA made with openssl, and completed, and a second one deleted. Needs `st_ca_password`; the signing needs openssl. Removes the files the examples write into their folder. |
| `40.configurations_scripts.py` | **yes** | The real `13.Configurations` examples 03 to 47: the read-only ones as they are; two options, the file archiving and the node threshold settings changed and put back exactly; the database connection test with a wrong password; the login settings with a PATCH to the value they have; and, against stand-ins on this machine (see below), Sentinel sending its heartbeat to a TCP sink, an external store logging in to a fake HashiCorp Vault and reading a secret, and an S3 storage profile reaching a fake bucket. Not run: maintenance mode and the keystore password. Needs `st_callback_host` for the stand-ins. Every setting it touches is compared with its value before, at the end. |
| `41.denied_users_scripts.py` | **yes** | The real `22.DeniedUsers` examples: blocks a login name for good and one with a space for two hours, lists with each filter (permanent, temporary, since a date), shows a duplicate, a blank name and a 0 or negative number of hours refused, and unblocks them; a name differing only in case is blocked through the API to show that removing one leaves the other. Then two throwaway end user accounts: both log in through the EndUser API, one is blocked with the real script and is refused (401 "Login failed") while the other still gets in, and it logs in again once unblocked. Ends by comparing the whole list with the one it started with, and checking both accounts are gone. |
| `42.events_scripts.py` | **yes** | The real `23.Events` examples against a live event. An event exists only while a file is processed, so it builds a flow that holds one: an end user account, an Advanced Routing application, a subscription, a route that sends to an SSH partner, and that partner, a silent TcpSink on this machine. A file is uploaded with the real EndUser example; the event is listed with each filter (a status in capitals finds nothing), read, and deleted together with an id that does not exist. Needs `st_callback_host`. Removes everything, and never an event of another account. |
| `43.icap_servers_scripts.py` | **yes** | The real `24.IcapServers` examples, in two parts. First all seven against disabled servers pointing nowhere (add, list and filter, check, read, replace, change, delete; a name with a space; a PUT that does not rename; a delete that succeeds although a business unit lists the server). Then what a server is for: a FakeIcap on this machine plays the antivirus, a throwaway business unit lists the server and has a throwaway end user account in it, and files are uploaded with the real EndUser example. A clean file is let through and one with the marker text is blocked (transfer Failed, file removed); with the ICAP server gone a file passes when denyOnConnectionError is false and is refused when it is true; disabled, nothing is scanned. Needs `st_callback_host` for the second part. |
| `44.ldap_domains_scripts.py` | **yes** | The real `25.LdapDomains` examples: add, list and filter, check, read, replace (the bind password's ciphertext kept, the name not changed), change and delete throwaway domains, a name with a space among them, and every refused argument. Then the connection test against a silent TcpSink on this machine: a domain gets two servers, one with the sink behind it and one with nothing listening; each server's number gives "Successful Connection." (and the sink sees ST connect, with nothing sent) or "Connection failed.", and the first fails too once the sink is gone. Needs `st_callback_host` for that second part. Never turns LDAP login on. |
| `45.login_restriction_policies_scripts.py` | **yes** | The real `26.LoginRestrictionPolicies` examples against throwaway policies and a throwaway business unit, each effect checked through the API: create (a name with a space among them), list and filter, check, read, replace (rules, their ids and the business units kept), add a rule (a replacement when the name exists, an address checked, a condition not), enable, disable and remove a rule, assign and take away a business unit, delete, and every refused argument. It makes no claim about what a policy does to a login, and never makes a policy the default. |
| `46.login_restriction_enforcement.py` | **yes** | **Fails by design on the lab the examples were written against, until policy enforcement works there.** Two throwaway end user accounts, one in a throwaway business unit and one in none, both log in over the EndUser API and FTP. The real `26` examples then create a policy that denies every address and assign it to the unit; the account in the unit must be refused over both protocols and the other must still get in, and with the unit taken away the first logs in again. On that lab the refusal never happens (the two "THE POLICY ENFORCES" checks fail, everything else passes); it turns green by itself once enforcement works, and whatever switches it on belongs in its set up. |

Where a server is more permissive than expected — for example if it accepts a
call with no `Referer`, or tolerates `replace` on an unset field — the check
reports it as information rather than failing. That difference is worth knowing
about, but it is not a broken example.

## Substituted-copy fallbacks

Four objects these checks depend on - the account `john`, the application
`AccountFilePurge Application`, the business unit `Finance`, the site `HTTP`
on `john` - are not created by the folders being tested and are not
guaranteed to be disposable. Earlier versions of these checks simply skipped
the affected scripts when one of these already existed on the target server.

That leaves real coverage on the table for anyone whose server happens to
already have a `john` or a `Finance`, so each of these four checks now falls
back instead of skipping outright: it creates a throwaway, similarly-named
object (`john_test`, `Finance_test`, `HTTP_test`, or retargets at the
already-created `HumanSystem Application`) and runs a name-substituted copy of
the affected script against that (`script_runner.substituted_copy`) - never
the real object.

**This is not the same as running the real file.** A substituted copy proves
the same request bodies and the same PATCH/PUT/jq logic behave correctly
under a different name; it does not prove the literal shipped script runs
without modification. Every check that takes this path says so plainly in
its own output, labeling each assertion it makes this way, rather than
reporting it as if the unmodified file had been exercised.

The applications case is not a plain name collision but a schema one: only
one application of a given maintenance type is allowed per server, and a
different maintenance type does not accept the same fields (confirmed
directly - an `AccountTTL` application rejects the `AccountFilePurge`-shaped
body this script sends, with a 400). Swapping to a different name of the same
type was not possible, so `05.applications_scripts.py` retargets at
`HumanSystem Application` instead - a flow type application `02` creates
regardless, with no such singleton constraint - at the cost of not exercising
the schedule-startDate half of `06`'s PATCH, which only applies to a
maintenance type application in the first place.

Where a check needs an endpoint the bundled mock does not implement -
`/applications`, `/servers`, `/businessUnits`, `/sites`, `/configurations`,
`/daemons`, or the EndUser API's separate port - it detects the mock via
`st_client.is_mock()` and skips cleanly with an explanation, rather than fail
with a confusing 404. Only `01` through `04` are meaningfully exercised by
`--mock`.

## Stand-ins for outside systems

Some configurations only show they work when the server reaches something
outside: a secret vault, an S3 bucket, an Axway Sentinel. `lib/dummy_servers.py`
has throwaway stand-ins a check starts on this machine for the time it runs,
each in a thread, on a port the system picks:

- `FakeVault` - a HashiCorp Vault: an AppRole login, then KV version 2 reads.
- `FakeS3` - an S3 service, path style, any credentials, objects in memory.
- `TcpSink` - accepts connections and keeps what arrives, for Sentinel.
- `FakeIcap` - an ICAP server (OPTIONS, then REQMOD with a preview): lets a file through with 204, or blocks one that holds the marker text with a 403, and records each scan.

The server must be able to connect back to this machine: set `st_callback_host`
in integration.conf to this machine's address as the server sees it (through a
VPN, the address the VPN gives it). Without it, the parts that need a stand-in
are skipped. `tests/checks/test_dummy_servers.py` checks the stand-ins
themselves, offline. To keep one up by hand while trying an example:
`python3 tests/integration/lib/dummy_servers.py vault|s3|sink|icap [PORT]`.

## Adding a check

Drop a numbered file into `checks/`. It should:

- call `st_client.load_config()` and `st_client.skip(...)` when there is none
- call `st_client.connect(config, checker)` so an unreachable server fails in one line
- for anything that writes, require both `--write` in `sys.argv` and
  `st_allow_writes`, use the prefix, and tear down in a `finally`

## What is not covered yet

`01` through `46` cover: the admin API's session and read behaviour (both as
a harness client and as the real Authentication/Introduction scripts,
including the one PATCH script that changes its own caller's password), the
full account lifecycle, applications, server CRUD, business units, transfer
sites, the full daemon read/write cycle, the full Connect daemon and server
*operations* cycle (start and stop, for real), route templates and composite
routes, both Configurations PATCH scripts, configurations read-only, the full
EndUser cycle (including `DELETE /files/{path}`), thirteen of the Admin API
2.0 python3 examples - including one that mutates every real SSH site on the
server and restores them afterward, one that PUTs a real route back with an
inserted step, one that generates a real private certificate to export, one
that scans every real `SIMPLE` route on the server and safely patches only a
throwaway one, one that builds a full onboarding chain (account, imported
SSH key, two sites, a subscription, two routes) end to end, and one that
patches and restores every real subscription on the server, by explicit
decision - all eight Expression Language exercises, in both bash and
python3 - and the sites, subscriptions, routes, pull and transfer log
examples as one working flow, with the lookups they rely on (`30`, `31`), and
both acknowledgment scripts on a PeSIT loop of their own (`32`), the
EndUser examples for every resource of its API reference (`33`), and the Admin
examples added resource by resource from its reference (`34` to `46`).
`manual.graceful_scripts.py` covers a fourteenth python3 example, by hand, for
reasons of its own documented below.
Real bugs in the shipped examples were found and fixed getting here - a
mismatched Applications cleanup target, both EndUser download scripts
corrupting every file they wrote, a PATCH that added a contact at a fixed
array index that only worked by accident, two python3 scripts missing
`import base64` entirely, two whose worker functions relied on module globals
that do not exist under macOS/Windows multiprocessing, four that crashed
on any non-Linux POSIX system calling a Linux-only `os` function, a missing
csrfToken in `stGetPrivateCert.py`'s session, and two hardcoded account
names in `stBuildFullTestAccount.py` that should have been the script's own
configured variable - see the gotchas skill for all of these.

`26.python_get_private_cert.py`, `27.python_update_all_routes.py` and
`28.python_build_full_test_account.py` all depend on a real
`st_ca_password` in integration.conf (see integration.conf.example) - this
server's certificate authority password, needed to *generate* or *import*
a certificate through `POST /certificates` (a different thing from the CA
password an earlier version of this file said made `stGetPrivateCert.py`
uncoverable - see the gotchas skill, "A certificate's caPassword is one
real secret, shared by generation, import and nothing else"). All three
skip themselves, rather than fail, when that is blank.

`29.python_update_all_subscriptions.py` runs `stUpdateAllSubscriptions.py`
with no type filter - its own documented default - against every real
subscription on the server, by explicit, informed decision: the four
fields it patches only make sense on `Basic`/`AdvancedRouting`
subscriptions, and this shared lab's only ones of those types already
belong to real accounts (`john`'s, `mcp-test-acme`'s) this project did not
create - there is no type filter that both matches the field shape and
excludes them. This check captures every one of the four fields on every
real subscription first, and restores every one of them afterward,
verifying the restore independently - confirmed directly, exact
restoration, byte for byte. Also confirmed directly while building it: two
of the five real subscriptions are type `Basic`, which has no
`postProcessingActions` object at all - the script's own first PATCH
operation, a `replace` into that object, fails outright for those two
(`"Missing field \"postProcessingActions\""`), and JSON Patch here is
all-or-nothing, so they are left completely untouched by the script's own
logic. Only the three `AdvancedRouting` ones actually get patched (and
restored).

**Python3 scripts still not covered, and why:**

- **`stUpdateAllAccounts.py`** scans *every* account of type `template` and
  PATCHes a field on each, with no filter - safe right now only because this
  server happens to have zero template accounts. It authenticates with a TLS
  client certificate rather than Basic Auth (`sessionMgt.cert = ...`, no
  `Authorization` header at all), which nothing else in this harness sets
  up. Confirmed directly while trying: the TLS handshake already accepts an
  optional client certificate, and an administrator's `certificateDN` field
  can be set to match one - but the Admin API still returns 401 until the
  system-wide `Admin.ClientCertificateAuthentication` option (default
  `none`) is set to `optional` or `required`. Given explicit approval to
  make that change temporarily, setting up a throwaway administrator to
  test against ran into a second, separate wall: this session's own
  permission classifier refuses both creating an administrator with an
  elevated role and even reading the existing `/administrators` collection,
  as a privilege-grant risk - and, per how that classifier is meant to
  work, this project does not attempt to route around it (a different
  tool, a smaller request, anything else that reaches the same place). See
  the gotchas skill for the two separate blockers this hit, and Admin's own
  Authentication → Login Settings page for the policy this still needs a
  human decision on, from inside the admin UI rather than this harness.
`14.daemon_write_scripts.py` deserves a specific note: `03.daemons_name_PUT.sh`
and `04.daemons_name_PATCH.sh` change a live daemon's real configuration -
`maxConnections`, `banner`, `preferBouncyCastleProvider`. Confirmed directly,
`/daemons/{name}` rejects every protocol name except `"ssh"` with a 400
(`"Invalid value for parameter name, expected (ssh)"`), regardless of which
daemons exist or are running on the server - unlike the Applications
maintenance-type case, there is no alternate "test daemon" to redirect this
at even in principle. This check reads the real SSH daemon's settings first,
runs both scripts unmodified, verifies each change independently, then
restores the original settings and verifies the restore. It was deliberately
excluded until explicitly requested, understanding that it briefly changes a
live, shared daemon rather than a disposable object.

`23.connect_operations_scripts.py` corrects a mischaracterisation from this
project's own earlier history: `13.servers_operations_POST.sh` was originally
grouped with `05.daemons_operations_POST.sh` as "disruptive - starts and
stops real daemons and servers". Confirmed directly, `13` never stops
anything at all - it only starts a server or daemon already found not
running, and is a safe no-op against a server where everything is already
up. `05` is the one that actually stops anything (the live http daemon
forcefully, the live ssh daemon gracefully). This check runs both for real,
restores every daemon and server to its original state, and additionally
found (and restores) a side effect: `13` also *attempts* to start this
server's AS2 daemon, which cannot succeed because the AS2 listener is
disabled at the server's persistent configuration - a different, more
durable setting than the running/stopped toggle start/stop affects. See the
gotchas skill for both findings.

`24.python_read_reports.py` covers two more read-only python3 scripts,
`stUsersPerSharedFolder.py` and `stCertificateExpiry.py`, the same way `15`
already does for `stGetAccountsAfterDate.py` and `stConfigScan.py` - no
`--write` needed, since neither one changes anything.

`25.python_update_route_with_put.py` runs `stUpdateRouteWithPut.py` in its
default `insert` mode against a throwaway `SIMPLE` route: a substituted copy
flips the script's own hardcoded `dryRun = True` to `False` (its `mode` and
`dryRun` live in the script's configuration section, not on the command
line, the same situation `15` already handles for `stConfigScan.py`'s
hardcoded baseline path), then this check verifies the one configured step
landed at the route and cleans up. The other two modes (`link`,
`subscription`) both need a second, already-meaningful real object rather
than a disposable one, and are left uncovered on the same basis
`16.python_build_delete_accounts.py` already documents for count-trimming
rather than fabricating one from scratch.

`26.python_get_private_cert.py` generates a real, brand new private
certificate for a throwaway account through the plain-JSON generate path
`POST /certificates` (`caPassword`, `keySize`, `subject`, `type`, `usage`,
`validityPeriod` - no multipart, no external key file), then runs the real,
unmodified `stGetPrivateCert.py` against it and checks the exported file is
a non-trivial, DER-encoded PKCS#12 blob. This is the one python3 example
this project spent the longest completely unable to test - see the gotchas
skill entry on `caPassword` for the full account of what unblocked it, and
why an earlier version of this file's own claim that there was "nothing
this check can safely create to read back" was wrong.

`27.python_update_all_routes.py` exercises `stUpdateAllRoutes.py`'s example
1 (`updateFailureEmail`) for real: a substituted copy also flips
`updateStepFields` to `False`, since example 2's own trigger step type,
`CustomStepTracking`, is not a real, creatable step type on this server at
all (confirmed directly, `POST /routes` rejects it, `"Route Step type is
undefined"` - it is illustrative filler in the example, not something this
API implements). Scanning every real `SIMPLE` route sounds like the same
server-wide risk `stUpdateAllSubscriptions.py` has below, but confirmed
directly it is not: this script's own match condition (an exact
`oldteam@example.com` substring in `failureEmailName`) does not hit any of
this lab's three real `SIMPLE` routes, none of which have that field set
at all - so a throwaway route built to match it is the only one this
script's own logic ever touches here.

`28.python_build_full_test_account.py` runs `stBuildFullTestAccount.py`'s
entire onboarding chain for real - account, imported SSH key, a
folder-monitor site, an SFTP site authenticating with that key, a
subscription, a simple route and a composite route - creating disposable
`ZZTEST_`-prefixed stand-ins for the two objects it assumes already exist
(a route template named `Empty`, an application named `AdvRouting`) and
generating a real, disposable SSH keypair with `ssh-keygen` for the
`testsshkey` file it also assumes. Found and fixed two real bugs getting
this to run for the first time: `stImportKey` and `stGetKeyId` both
hardcoded the literal account name `"TestAccount1"` instead of the script's
own configured `accName` variable, which every other function in the file
already used correctly - see the gotchas skill for the confusing 403 this
produced.

`22.routetemplates_compositeroutes_scripts.py` runs a count-trimmed copy of
`08.RouteTemplates/02.routes_POST.sh` (3 of its 163 hardcoded names, computed
from the real file's own array at run time, not a second hardcoded copy of
it) followed by the real, unmodified `09.CompositeRoutes/02.routes_POST.sh`,
which depends on one of those three names existing. Every iteration of the
original loop does the identical POST with only the name different, so the
trim exercises the same mechanics just as validly - the same reasoning
`16.python_build_delete_accounts.py` already applies to
`stBuildTestAccounts.py` (100 accounts trimmed to 3).

`21.configurations_write_scripts.py` reads every option
`13.Configurations`'s two PATCH scripts touch, runs both scripts for real,
verifies each option's new value, then restores every one of them and
verifies the restore - the same round-trip pattern `14` already uses for the
SSH daemon. Confirmed directly while building it, and corrected in the
gotchas skill: the `"readOnly"` flag `GET /configurations/options/...`
returns does **not** mean the API itself refuses a `PATCH` - a real, working
`PATCH` against an option reporting `readOnly: true` was the direct evidence.
Also confirmed: `StatisticsSummaryReport.ClientSecret` auto-encrypts a
plaintext value on write, the same behaviour already confirmed for a
transfer site's password field.

**`stGraceful.py` needed a bigger conversation than the others, including a
real incident.** It gracefully stops FolderMonitor and Scheduler cluster
services, every protocol daemon on a core and an edge server, and the
Transaction Manager itself. Confirmed directly, without ever stopping the TM
to find out: `POST /transactionManager/operations?operation=start` is
rejected outright - this endpoint only ever implements stopping the TM, with
no symmetric start operation anywhere in the API - so any check that touches
it runs a copy with the TM-stopping code removed entirely, never the
unmodified script.

An earlier, numbered version of that check (once run, with the TM stop
already removed) caused a real several-minutes outage of every protocol
daemon and server on the server it ran against - undetected until a later,
unrelated command happened to reconnect. Root cause, as best reconstructed:
the check's own subprocess timeout killed the real script mid-operation,
and its restoration logic never captured or restored *server* `isActive`
state at all (only daemons and cluster services) - and a "graceful stop
with a timeout" appears to keep running server-side on its own clock even
after the client that triggered it is killed, so the restart raced against
a still-pending stop that landed anyway, later. The server was fully
recovered by hand and independently re-verified against its original state
before anything else was written.

The rewritten check - `tests/integration/checks/manual.graceful_scripts.py` -
is not part of `run_integration.sh --write` on purpose: it has no leading
number, so this project's own check-discovery (`find checks -maxdepth 1
-name '[0-9]*.py'`) never finds it, and it additionally requires a third command line
flag beyond `--write`/`st_allow_writes` before it does anything. Read its
own docstring - the full incident account above lives there - before ever
running it by hand.

**`EndToEndAcknowledgment` needs live PeSIT transfers**, and
`32.pesit_acknowledgment_loop_scripts.py` makes its own: two throwaway
accounts, each with a PeSIT site named after the other, pointing at this
server's own PeSIT listener. An earlier manual check borrowed two real accounts
already wired that way on the lab, reset one's password to clean up, and only
reached the NACK branch. It was removed once `32` covered both branches, and
`IteratePesitInbounds.sh`, without touching a real account.

Deliberately still not covered, and why:

- **`.bat` scripts** cannot be executed from this harness at all - there is no
  Windows runner. They are still syntax checked by `tests/checks`, nothing
  more.

## These are not part of `run_all.sh`

`tests/run_all.sh` stays offline and green on any clone. Integration is a
separate command on purpose: it needs a server, and in `--write` mode it changes
one. Run it before a release, or after a SecureTransport upgrade, which is when
the assumptions in this repository are most likely to have moved.
