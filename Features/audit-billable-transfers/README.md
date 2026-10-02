# Audit and report on billable transfers

**Introduced in:** SecureTransport 5.5-20260924

SecureTransport classifies each transfer as billable or not, and that
classification is what the `ST.Transfers` usage count is built from. This is
visible three ways: the **Billable** column in **Operations > File Tracking**,
the `isBillable` filter on `GET /logs/transfers`, and an MCP-enabled AI
assistant reading the same endpoint.

**The rule, from the Admin Guide:**

- Every inbound transfer is billable.
- For a given file, the **first** outbound transfer that follows it is **not**
  billable.
- Every outbound transfer after that first one **is** billable.

**Note:** only transfers processed after the upgrade to 5.5-20260924 carry this
classification. A transfer from before the upgrade has no billable status, and
if the server is ever reverted to an earlier release, new transfers stop being
classified until it is upgraded again.

## What the examples here do

A test that puts the rule above through six scenarios, measures the billable
count before and after, and prints what it found:

1. **`billable_GET_report`** - today's billable count, and the six days before
   it, before anything runs.
2. **Six scenarios**, run as one pull each:

   | Scenario | File(s) | What happens |
   | -------- | ------- | ------------ |
   | 2.1 | `only_inbound.txt` | pulled in, nothing else |
   | 2.2 | `inbound_and_one_outbound.txt` | pulled in, pushed out once |
   | 2.3 | `inbound_and_two_outbounds.txt` | pulled in, pushed out twice, same partner |
   | 2.4 | `file_1_for_compress.txt`, `file_2_for_compress.txt` | pulled in together, compressed into `files_1_and_2_compressed.zip`, pushed out once |
   | 2.5 | `archive_with_2_files.zip` (containing `file_1_inside_archive.txt`, `file_2_inside_archive.txt`) | pulled in, decompressed, both files pushed out to one partner |
   | 2.6 | `archive_with_2_files_for_2_partners.zip` (containing `file_1_inside_archive_for_2_partners.txt`, `file_2_inside_archive_for_2_partners.txt`) | pulled in, decompressed, both files pushed to **two** partners |

3. **`billable_GET_report`** again - today's count should now be higher.
4. **Analysis** - the real measured delta for today (before vs after), printed
   alongside the rule above. It does **not** print a fixed per-scenario table:
   see [A complication specific to this test](#a-complication-specific-to-this-test-the-loopback-bills-twice)
   below for why one would be misleading.

### What the rule alone predicts for each scenario's pull and push

This is the billable count the rule above predicts for *just* each scenario's
own pull-into-`subscription/sN` and push-to-a-partner. It is **not** the full
picture - see the next section for what else this test's own setup adds.

| Scenario | Inbound | Outbound | Billable |
| -------- | ------: | -------: | -------: |
| 2.1 | 1 | 0 | 1 |
| 2.2 | 1 | 1 | 1 |
| 2.3 | 1 | 2 | 2 |
| 2.4 | 2 | 1 | 2 |
| 2.5 | 1 | 2 | 1 |
| 2.6 | 1 | 4 | 3 |
| **Total** | **7** | **10** | **10** |

Scenario 2.4's one outbound (the new archive) is its own first outbound, so it
is not billable even though both inputs were. Scenario 2.6's four outbounds are
two files to two partners each: the first arrival at either partner is free,
the second is billable, regardless of which partner it went to.

### A complication specific to this test: the loopback bills twice

**Confirmed directly, by reading this run's own File Tracking entries:**
billing is tracked **per transfer chain (`coreId`), not per filename.** Every
distinct `coreId` gets its own "first outbound is free" allowance. That matters
here because step 10's upload and step 11's pull are **two separate chains**
for the same file, not one:

1. **The upload** (step 10, over the End User API, into `/outbound-drop`) is
   itself a real, billable Inbound transfer. Nothing in the rule's plain
   six-scenario description accounts for it, because it is this test's own
   setup step, not one of the six scenarios.
2. **The pull removing that file from `/outbound-drop`** shares the upload's
   `coreId` - confirmed directly, the two entries carry the identical `coreId`
   - and is *that* chain's own free first outbound. Not billable.
3. **The pull landing in `/subscription/sN`** is a *different*, new `coreId`.
   Billable, same as every inbound.
4. **The push to the partner** shares *that* chain's `coreId`, and is *its*
   free first outbound. Not billable (for scenarios 2.2, 2.4 and the first
   partner of 2.6; billable for the genuinely repeated pushes in 2.3 and the
   second partner of 2.6, same as the table above).

So a file like `inbound_and_one_outbound.txt` is actually **2** billable
transfers once this test runs it (the upload, and the pull-landing), not the 1
the table above predicts for its pull/push alone - the table was never wrong
about the pull/push, it just never claimed to cover the upload.

This is a property of testing with a **loopback** (the "remote partner" is the
same account doing the uploading), not of the billing feature itself. A real
inbound file arriving from an actual external partner, with no prior upload
step by this same account, would not have this extra chain. Keep this in mind
when reading the per-day report: it will run ahead of the plain "6 scenarios,
10 billable transfers" arithmetic by roughly one extra billable transfer per
uploaded file.

To see the real, final numbers for a run, read **Operations > File Tracking**
for the test account, grouped by **Transfer** name, rather than trusting any
fixed prediction - which is exactly why step 4 prints the measured delta
instead of one.

## The design: one account, a loopback, no renaming

Like [Features/trigger-route-after-completed-pull](../trigger-route-after-completed-pull/),
the SecureTransport server is its own partner, so no other server is needed.
Unlike that feature, files here are **not** renamed on receive or send: the
whole point is recognising transfers by their exact file name in File Tracking,
so the names given above are exactly what reaches the server.

One test account (`btTestAccount`) owns everything:

```
/home/btTestAccount/
    outbound-drop/       every sample file and archive lands here
    subscription/
        s1/ .. s6/       one landing folder per scenario
    delivered-1/          the first "remote partner"
    delivered-2/          the second, used only by scenario 2.6
```

All six sample files sit in the **same** `outbound-drop` folder. Each scenario
has its own pull **site**, and each site's own download pattern matches only
the file(s) for its own scenario (for example, site 4's pattern is
`file_*_for_compress.txt`), so six sites can safely share one folder: a pull
copies a file rather than moving it, so one site's pull does not take a file
another site also needs.

## Running the examples

```
cd Features/audit-billable-transfers
cp settings.local.example.sh settings.local.sh      # Windows: settings.local.example.bat
$EDITOR settings.local.sh                             # set BT_ACCOUNT_PASSWORD
./00.run_all.sh                                       # or --cleanup to remove it all after
```

On Windows: `00.run_all.bat`. See
[Configuration](../../README.md#configuration) first if you have not set up the
Admin connection settings yet.

To run the setup by hand instead, the scripts are numbered 01 to 12 in the
order to run them, plus `billable_GET_report` (used before and after, not
part of that numbering) and `99.cleanup_DELETE`.

## Status

**Confirmed end to end against a real server**, including the full 00 to 12
flow, folder creation (top level and nested), the account, the eight sites,
the uploads (including both archives, built locally with `zip`), the
application, the `Compress` and `Decompress` route steps, and the billable
report.

Two things were wrong on the first real run, and are now fixed:

- `Compress` and `Decompress` ran correctly once `singleArchiveEnabled`,
  `singleArchiveName`, `compressionType`, `compressionLevel` and
  `filenameCollisionResolutionType` were set from the real schema - see
  `07.routes_POST_simple.sh`.
- `billable_GET_report` was reading `resultSet.returnCount`, which this
  endpoint (unlike `GET /accounts`, `GET /sites`, ...) caps at the request's
  own `limit`. With `limit=1` set to keep the response small, every day's
  count was silently capped at 1. Confirmed directly, by comparing against
  File Tracking's own count for the same account and day: the field that
  ignores `limit` is `resultSet.totalCount`, and that is what the script reads
  now.

[Back to all features](../README.md)
