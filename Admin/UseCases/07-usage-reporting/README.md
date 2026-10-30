# 07 Usage reporting

**Use case:** an administrator reports on the use of SecureTransport, or invoices for it. **Part 1** reads the use of the whole server: the active users, the usage report and the billable transfers of the transfer log. **Part 2** answers the next
question, which business unit used how much, with the one filter the API has for it.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`Admin/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

**Checked on:** SecureTransport 5.5-20260924. Where the text says "tried", it was run on the lab, a test server of this version. A statement marked "not tried" comes from the API reference, from the description of a setting, or from the product owner, and was not run.
The times and the date formats follow [Time formats in the SecureTransport REST API, and daylight saving time](../../../Features/Guidance/time-formats.md): read it first if a window of time or a date format is new to you.

## The two parts

| | Part 1: the whole server | Part 2: per business unit |
| - | ------------------------ | ------------------------- |
| Steps | 01 to 05, they only read | 06 to 11: 06, 07 and 99 write, the rest read |
| The question | How many users, how many transfers, and can I trust the numbers? | Which business unit consumed how much? |
| The calls | `GET /configurations/options`, `/statisticsSummary/activeUsers`, `/statisticsSummary/generateReport`, `/logs/transfers` | `GET /logs/transfers` with `businessUnit=` and `isBillable=true`, `GET /accounts?businessUnit=` |
| Objects | none | 3 business units, 6 accounts (`example_use_*`), and 100 transfers in the log |

`00.run_all.sh [DAYS]` runs everything and ends with `99.cleanup_DELETE.sh`. The scripts take their input as parameters, and say what they need when it is wrong, before any call. Part 2 uses the End User API for the transfers: set `ST_ENDUSER_PORT` in `set_variables.local.sh`
when it is not the admin port minus one.

## The three resources, and what each counts

| Resource | What it gives | Use it for |
| -------- | ------------- | ---------- |
| `GET /statisticsSummary/activeUsers` | The names of the users that did something in the last 60 days, and when | Counting active users |
| `GET /statisticsSummary/generateReport` | A usage report, one entry for each day: transfers, volume, active users | The numbers of the usage report |
| `GET /logs/transfers` | The transfer log, one entry for each transfer, with `isBillable` | Looking at the transfers behind a number, and cutting them by business unit |

They count different things, and none of them is a copy of another. The main points:

- An active user is counted by **name**, not by account. A deleted account stays in the list.
- The report cuts its days at midnight **in the server's time zone**.
- When you read a count from a list, read `resultSet.totalCount`. `returnCount` is the size of the page you asked for.
- Do not rebuild a report from the log: take the numbers for a report or an invoice from the report. The log is for looking at what is behind them.

## Part 1: the whole server

| Script | What it does | Copied from |
| ------ | ------------ | ----------- |
| `01.settings_GET` | The release, and the 15 `StatisticsSummaryReport*` settings that shape the report (a secret is not printed). | `13.Configurations/03.configurations_options_GET.sh`, `02.Introduction/01.version_GET.sh` |
| `02.activeUsers_GET [DAY]` | The active users in full, against the accounts that exist today, narrowed to a day, narrowed by name. | `33.StatisticsSummary/02.statisticsSummary_activeUsers_GET.sh` |
| `03.generateReport_GET [FROM] [TO]` | The usage report of a period, one line for each day, the summary checked against the days, and the four calls the server refuses. | `33.StatisticsSummary/01.statisticsSummary_generateReport_GET.sh` |
| `04.transfers_billable_count_GET [DAYS] [ACCOUNT]` | The billable transfers of the log for each day, the three values of `isBillable`, and `accountName=` against `account=`. | `16.TransferLogs/02.logs_transfers_GET_billable.sh` |
| `05.report_vs_log [DAYS]` | The report's `ST.Transfers` and the log's billable count side by side, for each day, with the difference. | |

### Active users (02)

A user that logs in and does something is an **active user**. The user stays in the list for 60 days after the last time it did something, and then it is removed. (The 60 days come from the product owner. They were not tried, because the oldest entry on the lab is 30 days old.)

- **The list is kept by name, not by account.** An account was created, used, deleted and created again with the same name. The second account got another id, and the list had **one** row for the name, with a later time.
- **A deleted account stays in the list.** On the lab, 729 of 740 names were no longer an account (the lab has 17 accounts). So the number of active users is not the number of accounts. It is the number of names that did something in the window. Step 02 prints both.
- **One page is 100 names.** With no `limit`, and with `limit=0`, the answer had 100 names and `totalCount` said 740. `limit=1000` returned all of them. Ask for the limit you want, and page with `offset` when the list is longer.
- **`lastAccessTime` is text, to the minute, with no offset.** It is the time of the server: a login at 06:57 server time (04:57 UTC) was listed as `6:57 AM`. It is not a form you can send back as a filter. `lastAdhocAccessTime` is a second time, empty for most users; what it records was not tried.
- **Filter by day** with `lastAccessTime.from` and `lastAccessTime.to`, in `yyyy-MM-dd` (the reference also lists a timestamp and RFC 2822). The day is the day in the server's time zone: a user last seen at 23:57 on 8 October is in `2026-10-08`, and one last seen at 00:39 on 9 October is in `2026-10-09`, although in UTC it is still the 8th.
- **The name filter is a "contains" match** that tells capitals from small letters: `name=ample_use` finds `example_use_a1`, and `name=EXAMPLE` finds nothing. `*` is **not** a wildcard in it (it is one in `/accounts` and in the transfer log): `name=*` finds 0. To pick a set of names, read the list whole and select by exact name, as 10 does.
- **It has no business unit.** `businessUnit=` on `activeUsers` is ignored without a word: the answer is the same as with none.

### The usage report (03)

```
GET /statisticsSummary/generateReport?startDate=24/10/2026&endDate=26/10/2026&includeActiveUsersCount=true&includeIncomingFileVolume=true
```

- The dates are `dd/MM/yyyy`, both days are in the report: the end date is **included**. A day written without the leading zero (`5/10/2026`) is accepted. The same day for both dates gives one entry. The call is quick: a year of days (366 entries) came back in 0.2 seconds.
- `includeActiveUsersCount` and `includeIncomingFileVolume` are optional and `false` by default. The reference says that, when they are false, `ST.ActiveUsers` and `ST.Volume` are in the report as 0. On the lab they were 0 also with both set to true.
- **A report you generate by hand includes today.** A report for 26 and 27 October, asked on the 27th, had 117 transfers for the 27th, and the log had 117 billable transfers for that day at that moment. The automatic report to the Amplify Platform does not include the current day (the description of `DaysToInclude`, not tried).

What the server refuses (all tried, all answer 400, and step 03 sends each and checks the answer):

| What you send | What the answer says |
| ------------- | -------------------- |
| No `endDate` | `'startDate' and 'endDate' parameters are mandatory.` |
| `startDate` after `endDate` | `Incorrect date frame. 'startDate' must be before 'endDate'.` |
| Dates in the future | `An error occur while generating report for the following date frame: ...` |
| `yyyy-MM-dd` | `Date 2026-10-23 is not in correct format. The correct format is: dd/MM/yyyy.` |

What is in the answer:

```text
{
  "envId": "Test_ID",
  "schemaId": "https://platform.axway.com/schemas/report.json",
  "timestamp": "2026-10-27T06:45:12.135+02:00",
  "granularity": 86400000,
  "report": {
    "2026-10-25T00:00:00.000+03:00": { "product": "SecureTransport", "usage": { "ST.ActiveUsers": 0, "ST.TransfersOut": 1089,
                                        "ST.TransfersIn": 774, "ST.Transfers": 1282, "ST.Volume": 0 }, "meta": {} },
    "2026-10-26T00:00:00.000+02:00": { ... }
  },
  "meta": { "companyName": "...", "productName": "SecureTransport", "productVersion": "5.5-20260924", "currentPatch": "UPDATE-20260924",
            "isECEnabled": true, "isADIEnabled": false, "plugins": { ... },
            "reportTimeframe": { "startDate": "2026-10-24T00:00:00.000+03:00", "endDate": "2026-10-27T00:00:00.000+02:00" },
            "reportSummary": { "ST.ActiveUsers": 0, "ST.TransfersOut": 1119, "ST.TransfersIn": 854, "ST.Transfers": 1370, "ST.Volume": 0 } }
}
```

- `granularity` is the size of an entry in milliseconds: 86,400,000, one day.
- **An entry is named by the start of its day in the server's time zone, with the offset of that moment.** The offset is `+03:00` on the 25th and `+02:00` on the 26th, because the clocks went back in between. The reference's example writes the names with `Z` (UTC); the lab answered with the offset of the server.
- `reportSummary` is the sum of the days (1282 + 88 = 1370 for `ST.Transfers`); step 03 checks it. `reportTimeframe.endDate` is the start of the day **after** your end date. `meta` also says who and what made the report: the company, the product and its version, the patch, the plugins, and whether the server is in an Enterprise Cluster and whether Advanced Data Intelligence is on.

This turns the answer into rows:

```python
def report_rows(report):
    """One (day, total, incoming, outgoing) per day of a generateReport answer, in order."""
    rows = []
    for day in sorted(report["report"]):
        usage = report["report"][day]["usage"]
        rows.append((day[:10], usage["ST.Transfers"], usage["ST.TransfersIn"], usage["ST.TransfersOut"]))
    return rows
```

**What the counters count.**

| Counter | What it is | Tried |
| ------- | ---------- | ----- |
| `ST.Transfers` | The number of **billable** transfers of the day | Equal to the count of `isBillable=true` in the log on 25, 26 and 27 October (1282, 88 and 117). Close on other days (see below). |
| `ST.TransfersIn` | The inbound transfers of the day | Equal to the billable inbound transfers of the log on three days (8, 26 and 27 October: 2954, 80 and 111), a few off on the others. |
| `ST.TransfersOut` | The outbound transfers of the day | Not rebuilt. See below. |
| `ST.ActiveUsers` | The active users of the day | 0 in every report, also with `includeActiveUsersCount=true`. What makes it count was not found. |
| `ST.Volume` | The incoming file volume | 0 in every report, also with `includeIncomingFileVolume=true`. |

The report against the log, day by day, on the lab (the log: billable transfers, and the billable ones among the incoming):

| Day | Report: transfers / in / out | Log: billable / billable in / outgoing in all | Log: billable out |
| --- | ---------------------------- | -------------------------------------------- | ----------------- |
| 6 Oct | 138 / 117 / 79 | 139 / 118 / 227 | 21 |
| 7 Oct | 98 / 98 / 6 | 89 / 89 / 219 | 0 |
| 8 Oct | 5240 / 2954 / 4913 | 5234 / 2954 / 7971 | 2280 |
| 9 Oct | 1705 / 1012 / 1415 | 1697 / 1002 / 2540 | 695 |
| 25 Oct | 1282 / 774 / 1089 | 1282 / 775 / 2061 | 507 |
| 26 Oct | 88 / 80 / 30 | 88 / 80 / 87 | 8 |
| 27 Oct (the day it was asked) | 117 / 111 / 11 | 117 / 111 / 35 | 6 |

The report's total follows the billable count of the log. It is equal on some days, and a few more or fewer on others (step 05 prints this for the days you ask for, and on 30 October it was 34 fewer in the report than in the log). The outbound number of the report is neither the outbound count of the log nor the billable outbound count.
Why the numbers differ was not found. For 25 October, none of these gave the report's 1089 outbound: the outgoing transfers by status, protocol, `serverInitiated`, `secure` and `resubmitted`; the distinct core ids (769), the distinct pairs of account and file name (928) and the distinct file names (467); the outgoing transfers with a size above 0 (1070).
So take the numbers for a report or an invoice **from the report**, and use the log to look at the transfers behind a day.

**The settings that shape the report** (step 01, read only):

| Setting | Value on the lab | What it does |
| ------- | ---------------- | ------------ |
| `StatisticsSummaryReport.AutomaticReport` | `true` | Generate and send the usage report to the Amplify Platform |
| `StatisticsSummaryReport.AutomaticReport.DaysToInclude` | `3` | The automatic report includes this number of days before today, and no data of today |
| `StatisticsSummaryReport.ActiveUsersCount` | `false` | Include the daily active users count in the report |
| `StatisticsSummaryReport.TransfersIn` | `true` | Include the inbound transfers in a report you generate by hand. It does not change the automatic report |
| `StatisticsSummaryReport.Volume` | `false` | Include the incoming volume in the report |
| `StatisticsSummaryReport.FilePath` | empty | A folder where the report files are saved at midnight. When empty, no file is saved |

The list also has the identity and the address of the Amplify Platform (`ClientId`, `ClientSecret`, `EnvironmentId`, `Platform.API`, ...). `ClientSecret` is a secret even in its encrypted form: do not paste the answer in a ticket as it is. Step 01 does not print it.

### Billable transfers in the log (04)

```
GET /logs/transfers?isBillable=true&account=john&startTimeAfter=Sun, 25 Oct 2026 00:00:00 +0300&endTimeBefore=Mon, 26 Oct 2026 00:00:00 +0200&limit=1&fields=id
```

```text
{ "resultSet" : { "returnCount" : 1, "totalCount" : 1282 }, "result" : [ ... ] }
```

- **Read `resultSet.totalCount`.** With `limit=1` the answer holds one transfer, so `returnCount` is 1. A script that counted `returnCount` counted 1 for every day.
- The window is `startTimeAfter` and `endTimeBefore`, in RFC 2822 with an offset. The [time formats guide](../../../Features/Guidance/time-formats.md) explains the offset, and the day on which the clocks change. Step 04 asks `date` for each midnight, and works with GNU `date` on Linux and with BSD `date` on macOS. If the machine is not in the time zone of the server, its days are not the server's days.
- **Filter by account with `account=`.** It is an exact match that ignores case, and `*` is a wildcard (`account=john*`). `accountName=` is **not** a filter: the answer to `accountName=no_such_account` held every transfer of the server (2873 on the day tried). A name that matches nothing in `account=` gives `totalCount` 0.
- **`isBillable` has three values.** On the day tried, 1282 transfers were billable, 1583 were not, and 8 had no value. The 8 are in neither count. `isBillable=true` and `isBillable=false` are filters; the 8 are the ones that are neither. Step 04 prints the three numbers for the last day.
- **A transfer from before the upgrade to a release that has the field has no billable status, and counts as 0.**

**The rule.** Every inbound transfer is billable. The first outbound transfer after it is not, and each later outbound is. This is applied for each **transfer chain**: the transfers that share one `coreId`. These facts come from [`Features/audit-billable-transfers`](../../../Features/audit-billable-transfers), which builds six scenarios and reports the billable count of each account:

- A **decompress** step keeps the chain of the archive. Two files unpacked from one archive and pushed out are two outbounds of one chain, so the second is billable.
- A **compress** step starts a new chain: the one push of the archive is free.
- A **pull** out of a partner account shares the chain of the upload into it. The pull that lands in the receiving account starts a new chain and is an inbound.
- A file **deleted through the End User API** is logged as an outgoing transfer under its `coreId`, and it is not billable. (This is why the cleanup of part 2, which empties the home folders, adds outgoing entries to the log.)

## Part 2: usage per business unit

**The story.** Three business units, two users in each. The users upload 100 files in all: 25 and 15 in the first unit, 20 and 15 in the second, 15 and 10 in the third. All 100 are inbound, so all 100 are billable. The server says the total, and the administrator asks which unit
consumed how much, and gets the answer from the billable transfers of the log, filtered by business unit.

| Script | What it does | Copied from |
| ------ | ------------ | ----------- |
| `06.business_units_POST` | Makes `example_use_bu1` to `bu3` and two accounts in each (`example_use_a1` to `f1`), each with the field `businessUnit`. | `12.BusinessUnits/01.businessUnits_POST.sh`, `05.Accounts/02.accounts_POST.sh` |
| `07.transfers_make_POST` | Keeps the time and what the report says for today, then the six accounts upload their 100 files with the End User API, and it waits until the log shows them. | `EndUser/UseCases/03-files-and-folders/02.files_POST_upload.sh` |
| `08.global_total_GET [FROM]` | The two global numbers: the billable transfers of the log after the time kept by 07, and how much more the report says for today than before. | |
| `09.business_unit_accounts_GET [BU]` | The accounts of a unit (`GET /accounts?businessUnit=`), and how the two APIs answer a unit that does not exist. | `05.Accounts/01.accounts_GET.sh`, `16.TransferLogs/01.logs_transfers_GET.sh` |
| `10.usage_per_business_unit_GET [BU] [FROM]` | The usage of one unit: its transfers, its billable and incoming transfers, the same for each account, and its active users. It checks that the accounts add up to the unit. | |
| `11.usage_all_business_units_GET [FROM]` | The table: for each unit its accounts, transfers, billable transfers and share of the server's billable transfers, then the sum, what is in no unit, and the whole server. | |
| `99.cleanup_DELETE` | Empties the home folders, deletes the six accounts and the three units by name, and the state files. Can be run twice. | |

A run on the lab, 11 at the end:

```text
  Business unit             Accounts  Transfers  Billable    Share
  example_use_bu1                  2         40        40   40.0%
  example_use_bu2                  2         35        35   35.0%
  example_use_bu3                  2         25        25   25.0%
  Finance                          0          0         0    0.0%
  all the units                    6        100       100  100.0%
  in no business unit             17          0         0    0.0%
  the whole server                23        100       100  100.0%
```

### What the API can give per business unit, and what it cannot

| Call | Business unit? | Tried |
| ---- | -------------- | ----- |
| `GET /logs/transfers` | **Yes: `businessUnit=NAME`**, "the business unit of the account, associated with the transfer". It works together with `isBillable`, `incoming`, the window and `account=`. | `businessUnit=example_use_bu1&isBillable=true` gave 40 of 100 |
| `GET /accounts` | Yes: `businessUnit=NAME`, and the field `businessUnit` of each account. | 2 accounts for `example_use_bu1` |
| `GET /statisticsSummary/generateReport` | **No.** The reference has `startDate`, `endDate` and two include flags. `businessUnit=` is ignored without a word: it answered 200 with the same `ST.Transfers` as with none (610 and 610). | step 08 |
| `GET /statisticsSummary/activeUsers` | **No.** `businessUnit=` is ignored: the answer is the same as with none. | |
| The other transfer log calls | The reference gives `businessUnit` to `/logs/transfers` only. `pullSummary` and the others were not tried with it. | |

So the report gives the total, and only the transfer log can be cut by business unit. What this means for the numbers:

- **The units do not add up to the report's total unless every account is in a unit.** Accounts that are in no unit are in the total and in no row. Step 11 prints that line: "in no business unit". On the lab 17 of the 23 accounts were in none, and they made no transfers in the window.
- **The report has whole days and the log has any window.** The table counts the transfers after the time 07 kept. The report for a day counts the whole day. A comparison is only fair when the window is the day, or when you take the report before and after, as 08 does.
- **The report counts the whole server.** On a server that other people use, the report grows by more than your 100, and so does the log count of 08. The rows of the units do not: they count the accounts of the units only.
- **A unit that does not exist is not answered the same way.** `GET /logs/transfers?businessUnit=nosuch` is 404 `Cannot find business unit with name nosuch.`, and `GET /accounts?businessUnit=nosuch` is 200 with nothing in it. An empty answer from the account list does not prove that the unit is there. Step 09 shows both.
- **A deleted unit is no longer found in the log.** `businessUnit=example_use_bu1` is 404 after the cleanup, although the transfers are still there: `account=example_use_a1` finds them. Report a unit's usage before you delete the unit.
- **The active users of a unit are not a call.** The list is by name, so step 10 reads it whole and counts the names of the unit's accounts.
- **Not tried:** whether a unit with child units counts the accounts and transfers of its children in its own `businessUnit=` filter. The lab has one unit that is not a throwaway, with no accounts.

## What to check

- [ ] The number of active users is the number of **names** in the list, not of accounts. A deleted account is still there for 60 days.
- [ ] The days of a report are the server's days. Say so next to a daily total, and if your time zone is not the server's, do not compare your own daily counts with it.
- [ ] The numbers of a report or an invoice come from the report. A count of the log is a check, not a copy.
- [ ] A count from a list is `resultSet.totalCount`, never `returnCount`.
- [ ] A filter by account is `account=`, never `accountName=`.
- [ ] A business unit is cut with `businessUnit=` on the transfer log. The report and the active users list have no such filter, and ignore it.
- [ ] The units are compared with the whole: the line "in no business unit" is part of every table.
- [ ] `ST.ActiveUsers` and `ST.Volume` are 0 unless they are switched on: read the settings (step 01) before you use them.

## What was not checked

- The 60 days of the active users list: the oldest entry on the lab is 30 days old.
- What `lastAdhocAccessTime` records.
- Why `ST.TransfersOut` is not the outbound count of the log, and why `ST.Transfers` differs by a few from the billable count on some days (34 on 30 October, a day when the lab was busy).
- What makes `ST.ActiveUsers` and `ST.Volume` report more than 0.
- How many hours the report counts for the day on which the clocks go back (25 hours). The lab had no transfers in the repeated hour.
- The automatic report to the Amplify Platform: its upload was not tried.
- A business unit with child units (see above).

## Tests

`tests/offline/checks/test_bash_admin_usecase_07.sh` runs every script against a stub `curl` and checks the call each one makes (the method, the URL, the exact query with the windows and the dd/MM/yyyy dates, the headers), that a count is read from `totalCount`, `account=` and not `accountName=`, the arithmetic of the units against sample answers,
the exit code and the message for each failure, the usage on a missing parameter, `00.run_all.sh` failing fast and still cleaning up, and the cleanup run twice. It also runs the date function and the report function of this README.
`tests/online/checks/75.admin_usecase_usage_reporting.py` runs the whole use case on a real server and reads what it made through its own session: the numbers of each unit (40, 35 and 25), the report's change, the refusals, and that nothing is left behind but the transfer log.
