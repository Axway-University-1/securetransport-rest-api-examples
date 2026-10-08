# Audit and report on billable transfers

**Introduced in:** SecureTransport 5.5-20260924

SecureTransport classifies each transfer as billable or not, and that
classification is what the `ST.Transfers` usage count is built from. This is
visible four ways: the **Billable** column in **Operations > File Tracking**,
the `isBillable` filter on `GET /logs/transfers`, an MCP-enabled AI assistant
reading the same endpoint, and the usage report, `ST.Transfers` in
`GET /statisticsSummary/generateReport` (one entry per day, for the whole
server, not per account: see
[`33.StatisticsSummary/01`](../../Admin/API%202.0/bash/33.StatisticsSummary/01.statisticsSummary_generateReport_GET.sh)).
`ST.Transfers` is the billable count, not `ST.TransfersIn` plus
`ST.TransfersOut`: one upload followed by two downloads of it adds 1 to In, 2
to Out and 2 to `ST.Transfers`, because the first outbound is free. Its
numbers follow the transfers within a few seconds.

**The rule, from the Admin Guide:**

- Every inbound transfer is billable.
- For a given file, the **first** outbound transfer that follows it is **not**
  billable.
- Every outbound transfer after that first one **is** billable.

"A given file" is a transfer chain: the transfers that share one `coreId` in
File Tracking. See [What a real run shows](#what-a-real-run-shows) for what
that means once a route compresses or unpacks a file.

**Note:** only transfers processed after the upgrade to 5.5-20260924 carry this
classification. A transfer from before the upgrade has no billable status, and
if the server is ever reverted to an earlier release, new transfers stop being
classified until it is upgraded again.

## The design: three accounts on one server

Every part of a transfer's journey happens in its own account, so each
account's billable count tells one part of the story, and can be checked
against the rule on its own. No other server is needed: the partners are
accounts on the same server, reached through its own SSH listener.

| Account | Its part | Its folders |
| ------- | -------- | ----------- |
| `partner_to_pull_from` | holds the sample files, which are uploaded to it | `<account>/outbound-drop` |
| the test account (`btTestAccount` by default, see [the test account's name](#the-test-accounts-name)) | pulls the files in, routes them, pushes them out: what is being measured | `subscription/s1` to `s6` |
| `partner_to_push_to` | receives the pushes, as two "remote partners" | `<account>/delivered-1`, `<account>/delivered-2` |

The test account owns everything else: the six pull sites (logging in as
`partner_to_pull_from`), the two push sites (logging in as
`partner_to_push_to`), the application, the subscriptions and the routes, all
named after it: `<account>PullSite1` to `6`, `<account>PushSitePartner1` and
`2`, `<account>Application`, `<account>PackageTemplate`,
`<account>SimpleRoute2` to `6` and `<account>CompositeRoute2` to `6`.

The partners are shared by every test account. Each test account keeps its
files in its own folder inside them, named after it, so two test accounts never
mix files, and the cleanup of one never touches the other's.

Files are **not** renamed on receive or send: the point is recognising
transfers by their exact file name in File Tracking.

## What the examples here do

1. **`billable_GET_report`**: the billable count per day of the three
   accounts, side by side, today and the six days before it.
2. **Six scenarios**, run as one pull each:

   | Scenario | File(s) | What happens |
   | -------- | ------- | ------------ |
   | 2.1 | `only_inbound.txt` | pulled in, nothing else |
   | 2.2 | `inbound_and_one_outbound.txt` | pulled in, pushed out once |
   | 2.3 | `inbound_and_two_outbounds.txt` | pulled in, pushed out twice, same partner |
   | 2.4 | `file_1_for_compress.txt`, `file_2_for_compress.txt` | pulled in together, compressed into `files_1_and_2_compressed.zip`, pushed out once |
   | 2.5 | `archive_with_2_files.zip` (containing `file_1_inside_archive.txt`, `file_2_inside_archive.txt`) | pulled in, unpacked, both files pushed out to one partner |
   | 2.6 | `archive_with_2_files_for_2_partners.zip` (containing `file_1_inside_archive_for_2_partners.txt`, `file_2_inside_archive_for_2_partners.txt`) | pulled in, unpacked, both files pushed to **two** partners |

3. **`billable_GET_report`** again.
4. **Analysis**: for each account, how many billable transfers the run added
   today, next to what the rule predicts, and whether they match.

## What the rule predicts, account by account

With one file each for scenarios 2.1 and 2.2:

| Scenario | `partner_to_pull_from`: uploads in | test account: pulls in | test account: billable pushes out | `partner_to_push_to`: arrivals |
| -------- | ---: | ---: | ---: | ---: |
| 2.1 | 1 | 1 | 0 | 0 |
| 2.2 | 1 | 1 | 0 of 1 | 1 |
| 2.3 | 1 | 1 | 1 of 2 | 2 |
| 2.4 | 2 | 2 | 0 of 1 | 1 |
| 2.5 | 1 | 1 | 1 of 2 | 2 |
| 2.6 | 1 | 1 | 3 of 4 | 4 |
| **Billable** | **7** | **7** | **5** | **10** |

So the run adds 7 billable transfers to `partner_to_pull_from`, 12 (7 + 5) to
the test account, and 10 to `partner_to_push_to`. More files for 2.1 and 2.2
add one to each column they pass through, which `00.run_all.sh` works out for
itself.

- `partner_to_pull_from`: each upload in is billable. Each pull out is that
  file's first outbound, so it is free.
- The test account: each pull in is billable. Of the pushes out, the first in
  each chain is free and the rest are billable.
- `partner_to_push_to`: each push arriving is an inbound transfer, so each is
  billable.

## What a real run shows

**Confirmed on a real 5.5-20260924 server** (one file each for 2.1 and 2.2):
the run added exactly 7, 12 and 10 billable transfers to the three accounts.
Reading the test account's File Tracking entries by `coreId` showed what
"a given file" means once a route changes the files:

- **Decompress keeps the archive's chain.** Both files unpacked from
  `archive_with_2_files.zip` carry the archive's `coreId`: the first push is
  free, the second is billable. In 2.6, the four pushes of the two unpacked
  files are one chain: one free, three billable.
- **Compress starts a new chain.** `files_1_and_2_compressed.zip` has a
  `coreId` of its own, so its one push is that chain's first outbound, and
  free.
- **The pull out of `partner_to_pull_from`** shares the upload's `coreId` and is
  that chain's free first outbound. **The pull into the test account** starts
  a new chain, billable as an inbound.
- **A file deleted through the End User API** is logged as an outgoing
  transfer under its `coreId`, and is never billable.

If a count differs from the prediction, `00.run_all.sh` says so. Read File
Tracking for that account, grouped by **Transfer** name. A push that was still
under way when the second report ran shows up there, and in a later report.

## Running the examples

```
cd Features/audit-billable-transfers
cp settings.local.example.sh settings.local.sh      # Windows: settings.local.example.bat
$EDITOR settings.local.sh                             # set BT_ACCOUNT_PASSWORD
./00.run_all.sh                                       # or --cleanup to remove it all after
```

`BT_ACCOUNT_PASSWORD` is the password of all three accounts.

`00.run_all.sh` takes three optional arguments, in this order:

```
./00.run_all.sh [ACCOUNT [INBOUND_ONLY [IN_AND_OUT]]] [--cleanup]

./00.run_all.sh test_account            a test account named test_account
./00.run_all.sh test_account 6 12       and scenario 2.1 with 6 files (inbound
                                        only), scenario 2.2 with 12 (in and out)
./00.run_all.sh test_account 6 12 --cleanup
```

- `ACCOUNT` is the test account to create and use. Without it the run starts
  with `btTestAccount`, and moves to another name when that one cannot be used:
  see [the test account's name](#the-test-accounts-name). The partners keep
  their names: they are shared.
- `INBOUND_ONLY` and `IN_AND_OUT` are how many files scenarios 2.1 and 2.2 run,
  1 each by default. With 1 the files keep their plain names
  (`only_inbound.txt`); with more they are numbered (`only_inbound_1.txt` to
  `only_inbound_6.txt`). The other four scenarios always run as described above.
- To clean up or report on a named account by hand, give it the same name:
  `./99.cleanup_DELETE.sh test_account`, `./billable_GET_report.sh after test_account`.
  If the run chose the name itself, use the one it printed (for example
  `./99.cleanup_DELETE.sh btTestAccount_2`), also after a run that stopped
  half way: a stopped run cleans up nothing.
- A partner that already exists, from another test account's run, is reused.
  `99.cleanup_DELETE.sh` removes only this test account's folder in each
  partner, and deletes a partner only when no other test account's site still
  logs in as it.
- The partners' counts include every test account's runs on the same day. Run
  one test account at a time to read them cleanly.

### The test account's name

You can run `./00.run_all.sh` with no arguments, again and again, and it works.
The reason it needs care: an account's home folder stays on disk, with its
owner, when the account is deleted. A new account with another uid (the
examples use 41733) cannot create a folder directly in such a home, and step 04
gets a 403 "Error occurred while creating file: null". Folders below an
existing one still work, which hides the cause. A lab that ran these examples
before the uid was changed from 1001 to 41733 has such a home for
`btTestAccount`, and the API cannot remove it.

So, when you did **not** choose a name, `00.run_all.sh` checks right after
step 01 whether the test account can create a folder in its home (a throwaway
folder, `bt_home_probe`, which it removes at once):

- **It can** (a new lab, or a home the account owns): nothing changes, the
  account is `btTestAccount`.
- **It cannot** (403 "Error occurred while creating file"): it says so, deletes
  only the test account, and moves to `btTestAccount_2`, then `_3` and so on up
  to `_9`, skipping a name that already exists as an account. The report,
  `--cleanup` and the `99.cleanup_DELETE.sh NAME` hint use the name it ended
  on. Partners are never deleted by this.
- **Any other result** (a failed login, a 403 with another message): no change.
  Step 04 reports it.

A name you choose (an argument, `BT_RUN_ACCOUNT`, or a `BT_TEST_ACCOUNT` other
than the default in `settings.local`) is never changed: step 04 stops with a
hint to use another name. Running the scripts by hand has no such check; give
step 01 and the rest a new name yourself. Every run leaves the empty home
folders of the names it used on the server: they are harmless.

On Windows: `00.run_all.bat`, with the same arguments. See
[Configuration](../../README.md#configuration) first if you have not set up the
Admin connection settings yet.

To run the setup by hand instead, the scripts are numbered 01 to 12 in the
order to run them, plus `billable_GET_report` (used before and after, not
part of that numbering) and `99.cleanup_DELETE`.

### Repeated client downloads

`files_GET_download.sh` (and `.bat`) is a separate experiment, not part of
`00.run_all.sh`. It downloads one file, as a client would, as many times as you
ask, in one End User API session. Each download is a transfer of its own, so it
shows how quickly repeated downloads add up in the usage reporting.

```
./files_GET_download.sh FILE [COUNT [ACCOUNT]]

./billable_GET_report.sh before
./files_GET_download.sh subscription/s1/only_inbound.txt 50
./billable_GET_report.sh after
```

- `FILE` is relative to the account's home folder, for example
  `subscription/s1/only_inbound.txt` in the test account after a run of
  `00.run_all.sh`, or `btTestAccount/delivered-1/inbound_and_one_outbound.txt`
  as `partner_to_push_to`.
- `COUNT` is how many times to download it, 1 by default.
- `ACCOUNT` is the account to log in as: the test account, `btTestAccount` by
  default, or a partner. Its password is `BT_ACCOUNT_PASSWORD`.

## Status

**Confirmed end to end against a real server**, including the full 00 to 12
flow with the three accounts, the cleanup, and the per-account counts above.

Three things were wrong in earlier versions, and are now fixed:

- `Compress` and `Decompress` ran correctly once `singleArchiveEnabled`,
  `singleArchiveName`, `compressionType`, `compressionLevel` and
  `filenameCollisionResolutionType` were set from the real schema - see
  `07.routes_POST_simple.sh`.
- `billable_GET_report` read `resultSet.returnCount`, which `/logs/transfers`
  caps at the request's own `limit`. With `limit=1`, every day's count was
  capped at 1. It reads `resultSet.totalCount` now.
- `billable_GET_report` filtered with `accountName=`, which `/logs/transfers`
  ignores without a word: every count was the whole server's, not the test
  account's. It filters with `account=` now, an exact match. An earlier version
  of this README called the report's numbers confirmed against File Tracking;
  they were not the account's own.

The earlier design used one account for everything, the server pulling from
and pushing to itself as that same account. Its counts mixed the uploads, the
pulls and the arrivals together, which is what the three accounts separate.

[Back to all features](../README.md)
