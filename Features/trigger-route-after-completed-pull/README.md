# Trigger route execution after a completed pull operation

**Introduced in:** SecureTransport 5.5-20260924

**Use case:** process all files retrieved during a pull as a single batch, after
the pull completes successfully.

Normally Advanced Routing starts once for each downloaded file. With this
feature, SecureTransport writes its own trigger file that lists every file the
pull retrieved. When the pull completes, that one file is submitted to the
subscription, and a single route execution processes all the files it names.

Use it when:

- several files must be processed together as one batch
- the route must start only after the whole pull has finished
- one route execution per file would be unnecessary overhead

## How it is configured (settings on the subscription)

1. Create or edit an Advanced Routing subscription.
2. Enable file retrieval from the transfer site.
3. Under **For Files Received from this Account or its Partners**, select
   **Create a file listing all pulled files**.
4. In **Create File As**, name the trigger file, for example
   `file_${date('yyyyddMMHHmmss')}.trigger` or `pull_results.trigger`.
5. Under **Post Transmission Settings**, select **Trigger route execution based
   on condition**.
6. Set the **Trigger condition** to match the trigger file, either its exact name
   or the tooltip example `${stenv['target'].matches('.*\\.trigger')?1:0}`.
7. For **Submit for processing**, select **Files read from trigger file
   content**, so only the files listed in the trigger file are processed.
8. Select the route that processes the files. If you want them in one archive,
   make the route's first step a **Compress** step.
9. Save.

## Flow of events

1. The scheduled or manual pull starts.
2. Every file matching the pull criteria is downloaded, and the trigger file is
   built as they arrive.
3. When the pull completes, the trigger file is submitted to the subscription.
4. The trigger condition is true, so Advanced Routing starts the route.
5. The route reads the file names from the trigger file and processes them.

**Result:** one route execution for the pulled files, however many there are.

## The examples

The test uses a **loopback**: the SecureTransport server is its own partner for
both the pull and the push, so you need no other server. One test account
(`arTestAccount`) owns everything, with three folders under its home:

```
/home/arTestAccount/
    outbound-drop/    the pull site downloads from here, standing in for a partner
    subscription/     the subscription folder: pulled files arrive here
    delivered/        the push site uploads here: the final destination
```

The folders in the sites, the subscription and the pull are written relative to
the home: `/outbound-drop`, `/subscription`, `/delivered`. A login to the server
starts in the account's home folder, so `/subscription` means
`/home/arTestAccount/subscription`. Writing the full path there makes the
subscription miss the files.

`delivered` is deliberately **not** the subscription folder. If it were, the
pushed files would look like new arrivals and the route would trigger itself
again and again.

Each example is a `.sh` and a `.bat`. Run them in order, or run them all with the
master script:

```
./00.run_all.sh [ACCOUNT] [--cleanup]

./00.run_all.sh                       # steps 1 to 13, leaves everything in place
./00.run_all.sh --cleanup             # the same, then removes everything (step 99)
./00.run_all.sh test_account          # the same, with a test account named test_account
```

On Windows: `00.run_all.bat`, with the same arguments. The master script
stops at the first step that fails, and does not clean up, so you can look. A
step fails when it exits 1, which every example does when the server refuses a
call, or when its output has a line starting `HTTP 4` or `HTTP 5`.

`ACCOUNT` is the test account to create and use. Without it the run starts with
`arTestAccount`, and moves to another name when that one cannot be used: see
[the test account's name](#the-test-accounts-name). The sites, routes,
application and subscription keep the names in `settings.sh` whatever the
account is called, so run one account at a time. To clean up a named account by
hand, give the same name: `./99.cleanup_DELETE.sh test_account`. If the run
chose the name itself, use the one it printed (for example
`./99.cleanup_DELETE.sh arTestAccount_2`), also after a run that stopped half
way: a stopped run cleans up nothing.

### The test account's name

You can run `./00.run_all.sh` with no arguments, again and again, and it works.
The reason it needs care: an account's home folder stays on disk, with its
owner, when the account is deleted. A new account with another uid (the
examples use 41733) cannot create a folder directly in such a home, and step 04
gets a 403 "Error occurred while creating file: null". Folders below an
existing one still work, which hides the cause. A lab that ran these examples
before the uid was changed has such a home for `arTestAccount`, and the API
cannot remove it.

So, when you did **not** choose a name, `00.run_all.sh` checks right after
step 01 whether the test account can create a folder in its home (a throwaway
folder, `ar_home_probe`, which it removes at once):

- **It can** (a new lab, or a home the account owns): nothing changes, the
  account is `arTestAccount`.
- **It cannot** (403 "Error occurred while creating file"): it says so, deletes
  only the test account, and moves to `arTestAccount_2`, then `_3` and so on up
  to `_9`, skipping a name that already exists as an account. The cleanup hint
  and `--cleanup` use the name it ended on.
- **Any other result** (a failed login, a 403 with another message): no change.
  Step 04 reports it.

A name you choose (an argument, `AR_RUN_ACCOUNT`, or an `AR_TEST_ACCOUNT` other
than the default in `settings.local`) is never changed: step 04 stops with a
hint to use another name. Running the scripts by hand has no such check; give
step 01 and the rest a new name yourself (`AR_TEST_ACCOUNT` in
`settings.local.sh`). The probe and the choice of the next name are shared with
`audit-billable-transfers`, in `Features/lib/home_folder.sh`.

| Step | Example | What it does |
| ---- | ------- | ------------ |
| 1 | `01.accounts_POST` | Creates the test account, with its own password |
| 2 | `02.sites_POST_pull` | Creates the pull site, an SSH site pointing at this server |
| 3 | `03.sites_POST_push` | Creates the push site, an SSH site uploading to `delivered` |
| 4 | `04.files_POST_folders` | Creates `outbound-drop` and `delivered` in the account's home, as the test account, with the End User API |
| 5 | `05.files_upload_POST` | Uploads three sample files to `outbound-drop`, as the test account, with the End User API |
| 6 | `06.routes_POST_template` | Creates the route package template |
| 7 | `07.routes_POST_simple` | Creates the simple route: one Send To Partner step to the push site |
| 8 | `08.applications_POST` | Creates the Advanced Routing application the subscription belongs to |
| 9 | `09.subscriptions_POST` | Creates the subscription with the settings above |
| 10 | `10.routes_POST_composite` | Creates the composite route: from the template, attached to the subscription, running the simple route |
| 11 | `11.transfers_pull_POST` | Runs the pull by hand |
| 12 | `12.files_PUT_triggerfile` | Rewrites the trigger file with the renamed file names, which re-triggers the subscription |
| 13 | `13.files_GET_result` | Lists the files in `outbound-drop`, `subscription` and `delivered`, waiting for the push to arrive |
| 99 | `99.cleanup_DELETE [ACCOUNT]` | Deletes the routes, subscription and application, the two sites, empties and removes `outbound-drop` and `delivered`, then deletes the test account |

### Before you run them

1. Set up the connection settings for the Admin examples. See
   [Configuration](../../README.md#configuration).
2. Choose a password for the test account:

   ```
   cd Features/trigger-route-after-completed-pull
   cp settings.local.example.sh settings.local.sh      # Windows: settings.local.example.bat
   $EDITOR settings.local.sh
   ```

   `settings.local.*` is ignored by git. The defaults (account name, folders,
   the SSH port 8022) are in `settings.sh` and `settings.bat`.
3. Nothing else to prepare: step 4 creates the two folders.

### Things to know

- The sites connect to this server's **SSH port, 8022**, which is not the REST
  API port. If the pull cannot log in, first check whether your server lets an
  account open an SSH session to itself. Some deployments forbid it.
- Steps 4 and 5 use the **End User API**, on its own port (8443 by default,
  `AR_ENDUSER_PORT`), not the Admin port (444 on a root install). Unlike the
  Admin API it needs a real login: they log in once as the test account, keep
  the session cookie and `csrfToken`, and log out at the end. The content call uses
  `PUT` with `application/octet-stream`; POST is refused with a 415.
- Deleting an account does **not** delete the files in its home folder. After a
  run, `delivered` still holds its files, and a new test account with the same
  home will see them.

### Telling the transfers apart

One account does the pull and the push, so File Tracking shows each file as
several near-identical rows. The two sites rename the files to tell them apart:
the pull site renames each file as it arrives, with `doAsIn`, and the push site
renames it as it is sent, with `doAsOut`. A file `pull_test_1.txt` becomes
`pull_test_1.txt_PULLED` in the subscription folder, and
`pull_test_1.txt_PULLED_PUSHED` in `delivered`. The suffixes are
`AR_PULLED_SUFFIX` and `AR_PUSHED_SUFFIX` in the settings.

### The trigger file

The subscription's trigger file is named `file_${date('yyyyddMMHHmmss')}.trigger`.
SecureTransport evaluates the `${date(...)}` part itself, once per pull, when it
creates the file. The date pattern and the trigger condition are written once, in
`settings.sh` and `settings.bat`, so the condition always matches the name:

```
${stenv['target'].matches('.*\\.trigger')?1:0}
```

The two backslashes are the expression language's string rule. The examples
build the JSON with `jq` or PowerShell, which escape it again correctly.

### Saved ids

Steps 6 to 10 save the ids of what they create in `state.local.sh` (or `.bat`),
which git ignores, and later steps read them. Step 99 does not need that file: it
finds everything by the names in the settings, so it still works if the file is
lost or the steps were run more than once.

### When the cleanup cannot remove everything

`99.cleanup_DELETE` exits 1 when the server refuses a delete, when a list it
needs cannot be read, or when it cannot tell whether the account exists. It
names what is left, keeps `state.local.sh`, and can be run again. Something that
is already gone (HTTP 404) is not a failure. It exits 0, and removes the saved
ids, only when everything it looked for is gone.

### Checking the result

Steps 1 to 11 have been run against a real SecureTransport 5.5-20260924. Step 11
only *starts* the pull. The pull, the trigger file, the route and the push all
happen afterwards, asynchronously, so step 11 prints nothing about them. Run
step 13 to see the result, and check:

- the three sample files left `outbound-drop` and arrived in the subscription
  folder, and a `file_<date>.trigger` file was created listing them
- **one** route execution ran for the whole pull, not one per file
- the three files are in `delivered`

Then run `99.cleanup_DELETE` to remove everything. It leaves the files in the
account's home folder, as deleting an account does not remove them.

[Back to all features](../README.md)
