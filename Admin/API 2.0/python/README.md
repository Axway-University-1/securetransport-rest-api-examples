# Python examples (Admin API)

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer) before you run anything. The settings are in
> the `config` file you copy from `config.example`: see [Configuration](../../../README.md#configuration).

The python examples are whole programs for real maintenance tasks, rather than
single calls. They are CSRF aware, as required from the 20230525 release onwards:
each logs in once and sends the `csrfToken` of the login on every later call, the
logout included. The lab accepts a write without it, which hid a script that
forgot, so `tests/offline/checks/test_python_scripts_run.py` runs every one of them as a
whole against a fake server that refuses such a write. The same test checks the
exit codes: a failure exits 1 (a bad argument 2), never 0, and a connection error
or a timeout always ends the script.

| Script | What it does |
| ------ | ------------ |
| `stBuildFullTestAccount.py` | Onboards one account end to end: account, certificate, transfer site, routes and subscription. The best place to start if you are automating onboarding. |
| `stBuildTestAccounts.py` | Creates accounts in bulk, using multiprocessing. A dry run unless `--apply`; the prefix and the number are arguments. |
| `stDeleteTestAccounts.py` | Deletes the user accounts whose name starts with a prefix (`ZZ`, what `stBuildTestAccounts.py` makes), in bulk. Lists them and deletes nothing unless `--apply`. |
| `stGetAccountsAfterDate.py` | Lists accounts created after a given date. |
| `stUpdateAllAccounts.py` | Scans every template account and updates a field. Uses certificate based authentication rather than basic auth. |
| `stUpdateAllRoutes.py` | Scans every simple route and patches a field on the route, or a field inside one of its steps. |
| `stUpdateRouteWithPut.py` | Reads a route, changes it and writes the whole object back. Inserts steps, links a simple route into a composite, or attaches a route to a subscription. |
| `stUpdateAllSubscriptions.py` | Scans every subscription and patches a set of fields. |
| `stUsersPerSharedFolder.py` | Reports which accounts have access to each shared folder, by joining applications and subscriptions. Read only. |
| `stReplaceSites.py` | Scans SSH transfer sites and updates their cipher suites. |
| `stCertificateExpiry.py` | Counts the certificates and reports the ones that have expired or are about to. Read only. |
| `stBillableTransfers.py` | Counts the billable transfers per day, for every account or for one. Needs 5.5-20260924 or later. Read only. |
| `stGetPrivateCert.py` | Exports a certificate and its private key by ID, as a PKCS#12 file readable by its owner only. The password for the file comes from the environment or a prompt, never from the command line or the URL. |
| `stAddLoginRestrictionRule.py` | Adds a rule to an existing login restriction policy. |
| `stConfigScan.py` | Baselines the server configuration (as JSON) and reports drift from the baseline on later runs, in both directions. Useful after a patch. |
| `stGraceful.py` | Gracefully drains and shuts down a core and edge pair, **the Transaction Manager included, which the API cannot start again**. Stops nothing without `--yes`, and not the Transaction Manager unless every daemon went down in time. |

The scripts that create, change or delete many objects at once —
`stUpdateAllRoutes.py`, `stUpdateAllSubscriptions.py`, `stUpdateRouteWithPut.py`,
`stUpdateAllAccounts.py`, `stReplaceSites.py`, `stBuildTestAccounts.py` and
`stDeleteTestAccounts.py` — are a dry run by default: they say what they would send
and send nothing. Read that output, then give `--apply` (or set `dryRun` to `False`
in the configuration section) to let them write. `stGraceful.py` has no dry run to
fall back on: it needs `--yes` and does nothing without it.

Optional keys of the `config` file (see `config.example`): `st_ca_bundle` or
`st_verify=yes` turn on the check of the server's certificate, which the examples
leave off by default so that a lab with a self signed certificate works.

## utils

`utils` holds two tools whose input is an exported `systemConfiguration.xml`
rather than the live API:

| Script | What it does |
| ------ | ------------ |
| `stCompareExportedConfigurations.py` | Compares two exported configurations and reports the options whose value differs, and the options present in only one of them. Useful when you have the exports but no access to the system. |
| `processSystemConfig.py` | Extracts the user classes from an export and converts their membership expressions from the 5.2.1 format to the 5.5 format. Writes the result as XML, and can create the user classes on a target server through the API when `createOnTarget` is set. |

Export the configuration from the GUI, then take the XML out of the zip it
produces:

```
unzip -j export_configuration.zip systemConfiguration.xml -d /home/axway/api
```
