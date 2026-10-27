# Usage and billing reporting: what the numbers mean

**For:** administrators who report on the use of SecureTransport, or who invoice for it.
**Checked on:** SecureTransport 5.5-20260924. Where the text says "tried", it was run on a lab server of this version. A statement marked "not tried" comes from the
API reference, from the description of a setting, or from the product owner, and was not run. In this guide, "the lab" is the test server that it was checked on.

## Summary

Three resources of the Admin API give numbers about use. They count different things, and none of them is a copy of another.

| Resource | What it gives | Use it for |
| -------- | ------------- | ---------- |
| `GET /statisticsSummary/activeUsers` | The names of the users that did something in the last 60 days, and when | Counting active users |
| `GET /statisticsSummary/generateReport` | A usage report, one entry for each day: transfers, volume, active users | The numbers of the usage report |
| `GET /logs/transfers` | The transfer log, one entry for each transfer, with `isBillable` | Looking at the transfers behind a number |

The main points:

- An active user is counted by **name**, not by account. A deleted account stays in the list.
- The report cuts its days at midnight **in the server's time zone**.
- On the lab, `ST.Transfers` in the report was equal to the number of billable transfers in the log on three days (25, 26 and 27 October). On the other days it was close. `ST.TransfersOut`
  could not be rebuilt from the log. Do not rebuild a report from the log: take the numbers from the report.
- When you read a count from a list, read `resultSet.totalCount`. `returnCount` is the size of the page you asked for.

All times in this guide follow the [time formats guide](time-formats.md). Read it first if a window of time or a date format is new to you.

- [Active users](#active-users)
- [The usage report](#the-usage-report)
- [Billable transfers in the log](#billable-transfers-in-the-log)
- [Checklist](#checklist)

## Active users

### What is counted

A user that logs in and does something is an **active user**. The user stays in the list for 60 days after the last time it did something, and then it is
removed. (The 60 days come from the product owner. They were not tried here, because the oldest entry on the lab is only 30 days old.)

What was tried:

- **The list is kept by name, not by account.** An account was created, used, deleted, and created again with the same name. The second account got another id.
  The list had **one** row for the name, and its time moved from 7:04 to 7:05.
- **A deleted account stays in the list.** After the delete, the row was still there. On the lab, 700 of the names in the list were no longer an account. The lab
  has 17 accounts and the list had more than 700 rows.
- **So the number of active users is not the number of accounts.** It is the number of names that did something in the window.

### Reading the list

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/statisticsSummary/activeUsers" \
  --data-urlencode "limit=1000" -H "accept: application/json" -H "Referer: x"
```

```text
{
  "resultSet" : { "returnCount" : 716, "totalCount" : 716 },
  "result" : [ {
    "name" : "newAccountTest",
    "lastAccessTime" : "October 8, 2026, 9:36 AM",
    "lastAdhocAccessTime" : ""
  }, ... ]
}
```

- **One page is 100 names.** Without `limit`, and with `limit=0`, the answer had 100 names and `totalCount` said 716. `limit=1000` returned all 716. Ask for the limit you
  want, and page with `offset` when the list is longer.
- **`lastAccessTime` is text, to the minute, with no offset.** It is the time of the server: a login at 06:57 server time (04:57 UTC) was listed as `6:57 AM`. It
  is not a form you can send back as a filter.
- **`lastAdhocAccessTime`** is a second time, empty for most users. What it records was not tried.

### Filtering by day

The `lastAccessTime.from` and `lastAccessTime.to` filters take `yyyy-MM-dd`, a timestamp or RFC 2822 (reference). Tried with `yyyy-MM-dd`: the day is the day in the server's
time zone. A user last seen at 23:57 on 8 October is in `2026-10-08`. A user last seen at 00:39 on 9 October is in `2026-10-09`, although in UTC it is still the 8th.

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/statisticsSummary/activeUsers" \
  --data-urlencode "lastAccessTime.from=2026-10-09" --data-urlencode "lastAccessTime.to=2026-10-09" \
  --data-urlencode "limit=1000" -H "accept: application/json" -H "Referer: x"
```

The answer has the names last seen on 9 October.

## The usage report

### Asking for it

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/statisticsSummary/generateReport" \
  --data-urlencode "startDate=24/10/2026" --data-urlencode "endDate=26/10/2026" \
  --data-urlencode "includeActiveUsersCount=true" --data-urlencode "includeIncomingFileVolume=true" -H "accept: application/json" -H "Referer: x"
```

- The dates are `dd/MM/yyyy`. Both days are in the report: the end date is **included**.
- `includeActiveUsersCount` and `includeIncomingFileVolume` are optional and `false` by default. The reference says that, when they are false, `ST.ActiveUsers` and
  `ST.Volume` are in the report as 0.
- The call is quick: a year of days (366 entries) came back in 0.2 seconds.

What is refused (all tried, all answer 400):

| What you send | What the answer says |
| ------------- | -------------------- |
| No `endDate` | `'startDate' and 'endDate' parameters are mandatory.` |
| `startDate` after `endDate` | `Incorrect date frame. 'startDate' must be before 'endDate'.` |
| Dates in the future | `An error occur while generating report for the following date frame: ...` |
| `yyyy-MM-dd` | `Date 2026-10-23 is not in correct format. The correct format is: dd/MM/yyyy.` |

The same day for both dates is accepted and gives one entry. A day written without the leading zero (`5/10/2026`) is accepted too.

### What is in the answer

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
- **An entry is named by the start of its day in the server's time zone, with the offset of that moment.** The offset is `+03:00` on the 25th and `+02:00` on the 26th, because the clocks went
  back in between. The reference's example writes the names with `Z` (UTC); the lab answered with the offset of the server.
- `reportSummary` is the sum of the days. On the lab it was: 1282 + 88 = 1370 for `ST.Transfers`.
- `meta` says who and what made the report. It holds the company, the product and its version, the patch, and the plugins installed. It also says whether the server is in an Enterprise Cluster and whether Advanced Data
  Intelligence is on.
- `reportTimeframe.endDate` is the start of the day **after** your end date.
- **A report you generate by hand includes today.** A report for 26 and 27 October, asked on the 27th, had 117 transfers for the 27th. The log had the same number, 117 billable transfers, for
  that day at that moment. The automatic report to the Amplify Platform does not include the current day (the description of `DaysToInclude`, not tried).

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

### What the counters count

| Counter | What it is | Tried |
| ------- | ---------- | ----- |
| `ST.Transfers` | The number of **billable** transfers of the day | Equal to the count of `isBillable=true` in the log on 25, 26 and 27 October (1282, 88 and 117). Close on other days (see below). |
| `ST.TransfersIn` | The inbound transfers of the day | Equal to the billable inbound transfers of the log on three days (8, 26 and 27 October: 2954, 80 and 111), a few off on the others (see the table). |
| `ST.TransfersOut` | The outbound transfers of the day | Not rebuilt. See below. |
| `ST.ActiveUsers` | The active users of the day | 0 in every report, also with `includeActiveUsersCount=true`. What makes it count was not found. |
| `ST.Volume` | The incoming file volume | 0 in every report, also with `includeIncomingFileVolume=true`. |

A comparison of the report with the log, day by day, on the lab (the log: billable transfers, and the billable ones among the incoming):

| Day | Report: transfers / in / out | Log: billable / billable in / outgoing in all | Log: billable out |
| --- | ---------------------------- | -------------------------------------------- | ----------------- |
| 6 Oct | 138 / 117 / 79 | 139 / 118 / 227 | 21 |
| 7 Oct | 98 / 98 / 6 | 89 / 89 / 219 | 0 |
| 8 Oct | 5240 / 2954 / 4913 | 5234 / 2954 / 7971 | 2280 |
| 9 Oct | 1705 / 1012 / 1415 | 1697 / 1002 / 2540 | 695 |
| 25 Oct | 1282 / 774 / 1089 | 1282 / 775 / 2061 | 507 |
| 26 Oct | 88 / 80 / 30 | 88 / 80 / 87 | 8 |
| 27 Oct (the day it was asked) | 117 / 111 / 11 | 117 / 111 / 35 | 6 |

What this shows: the report's total follows the billable count of the log. It is equal on some days, and a few more or fewer on others. The outbound number of the
report is neither the outbound count of the log nor the billable outbound count. Why the numbers differ was not found. For 25 October, none of these gave the report's 1089 outbound:

- the outgoing transfers by status, protocol, `serverInitiated`, `secure` and `resubmitted`;
- the distinct core ids (769), the distinct pairs of account and file name (928) and the distinct file names (467);
- the outgoing transfers with a size above 0 (1070).

So:

- Take the numbers for a report or an invoice **from the report**, not from a count of the log.
- Use the log to look at the transfers behind a day, not to rebuild it.

### The settings that shape the report

Read-only: `GET /configurations/options?name=StatisticsSummaryReport*` lists them.

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations/options" \
  --data-urlencode "name=StatisticsSummaryReport*" --data-urlencode "limit=100" -H "accept: application/json" -H "Referer: x"
```

The answer has the value of each setting and its description. The ones that matter here (values from the lab, the description is the product's):

| Setting | Value on the lab | What it does |
| ------- | ---------------- | ------------ |
| `StatisticsSummaryReport.AutomaticReport` | `true` | Generate and send the usage report to the Amplify Platform |
| `StatisticsSummaryReport.AutomaticReport.DaysToInclude` | `3` | The automatic report includes this number of days before today, and no data of today |
| `StatisticsSummaryReport.ActiveUsersCount` | `false` | Include the daily active users count in the report |
| `StatisticsSummaryReport.TransfersIn` | `true` | Include the inbound transfers in a report you generate by hand. It does not change the automatic report |
| `StatisticsSummaryReport.Volume` | `false` | Include the incoming volume in the report |
| `StatisticsSummaryReport.FilePath` | empty | A folder where the report files are saved at midnight. When empty, no file is saved |

The list also has the identity and the address of the Amplify Platform (`ClientId`, `ClientSecret`, `EnvironmentId`, `Platform.API`, ...). `ClientSecret` is a secret even
in its encrypted form: do not paste the answer in a ticket as it is.

## Billable transfers in the log

### Counting

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
  --data-urlencode "isBillable=true" --data-urlencode "account=john" \
  --data-urlencode "startTimeAfter=Sun, 25 Oct 2026 00:00:00 +0300" --data-urlencode "endTimeBefore=Mon, 26 Oct 2026 00:00:00 +0200" \
  --data-urlencode "limit=1" --data-urlencode "fields=id" -H "accept: application/json" -H "Referer: x"
```

```text
{ "resultSet" : { "returnCount" : 1, "totalCount" : 1282 }, "result" : [ ... ] }
```

- **Read `resultSet.totalCount`.** With `limit=1` the answer holds one transfer, so `returnCount` is 1. A script that counted `returnCount` counted 1 for every day.
- The window is `startTimeAfter` and `endTimeBefore`, in RFC 2822 with an offset. The [time formats guide](time-formats.md) explains the offset and the day on which the clocks
  change.
- **Filter by account with `account=`.** It is an exact match that ignores case, and `*` is a wildcard (`account=john*`). `accountName=` is **not** a filter: the answer
  to `accountName=no_such_account` held every transfer of the server (2873 on the day tried). A name that matches nothing in `account=` gives `totalCount` 0.
- **`isBillable` has three values.** On the day tried, 1282 transfers were billable, 1583 were not, and 8 had no value. The 8 are in neither count: 1282 + 1583 is 2865 of
  2873. `isBillable=true` and `isBillable=false` are filters; the 8 are the ones that are neither.

### The rule

Every inbound transfer is billable. The first outbound transfer after it is not, and each later outbound is. This is applied for each **transfer chain**: the transfers that
share one `coreId`. These facts come from the example `Features/audit-billable-transfers`, which reads each transfer's `coreId`:

- A **decompress** step keeps the chain of the archive. Two files unpacked from one archive and pushed out are two outbounds of one chain, so the second is billable.
- A **compress** step starts a new chain: the one push of the archive is free.
- A **pull** out of a partner account shares the chain of the upload into it. The pull that lands in the receiving account starts a new chain and is an inbound.
- A file **deleted through the End User API** is logged as an outgoing transfer under its `coreId`, and it is not billable.

To see the rule at work, run `Features/audit-billable-transfers`: it builds six scenarios and reports the billable count of each account.

### Counting by account and day

This reads the count for each day of a window with the billable filter. It asks `date` for each midnight, as the time formats guide explains. The function works with GNU
`date` on Linux and with BSD `date` on macOS:

```bash
midnight_ago() {
  if date -v-1d >/dev/null 2>&1; then
    if [ "$1" -ge 0 ]; then date -v-"$1"d -v0H -v0M -v0S -R; else date -v+"$((-$1))"d -v0H -v0M -v0S -R; fi
  else
    date -d "$1 days ago 00:00:00" -R
  fi
}
for N in 3 2 1 0; do
  START=$(midnight_ago "${N}"); END=$(midnight_ago "$((N - 1))")
  COUNT=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
    --data-urlencode "isBillable=true" --data-urlencode "startTimeAfter=${START}" --data-urlencode "endTimeBefore=${END}" \
    --data-urlencode "limit=1" --data-urlencode "fields=id" -H "accept: application/json" -H "Referer: x" | jq -r '.resultSet.totalCount')
  echo "${START}  ${COUNT}"
done
```

## Checklist

- [ ] The number of active users is the number of **names** in the list, not of accounts. A deleted account is still there for 60 days.
- [ ] The days of a report are the server's days. Say so next to a daily total, and if your time zone is not the server's, do not compare your own daily counts with it.
- [ ] The numbers of a report or an invoice come from the report. A count of the log is a check, not a copy.
- [ ] A count from a list is `resultSet.totalCount`, never `returnCount`.
- [ ] A filter by account is `account=`, never `accountName=`.
- [ ] `ST.ActiveUsers` and `ST.Volume` are 0 unless they are switched on: read the settings above before you use them.

## What was not checked

- The 60 days of the active users list: the oldest entry on the lab is 30 days old.
- What `lastAdhocAccessTime` records.
- Why `ST.TransfersOut` is not the outbound count of the log, and why `ST.Transfers` differs by a few from the billable count on some days.
- What makes `ST.ActiveUsers` and `ST.Volume` report more than 0.
- How many hours the report counts for the day on which the clocks go back (25 hours). The lab had no transfers in the repeated hour.
- The automatic report to the Amplify Platform: its upload was not tried.
