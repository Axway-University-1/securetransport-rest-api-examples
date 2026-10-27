# Time formats in the SecureTransport REST API, and daylight saving time

**For:** administrators and integrators who script against the REST API, or who build reports and scheduled jobs on it.
**Checked on:** SecureTransport 5.5-20260924. Where the text says "the server does", it was tried on this version only. A statement marked "not tried"
comes from the API reference and was not run.

## Summary

The REST API does not use one date format. It uses five, and which one you send depends on the resource. Some of them carry a time zone offset, and some
are a date only. This guide first lists the formats and which resource takes which, with an example of each. Then it explains what that means when the
clocks change (daylight saving time), because a script that builds a window of time in the wrong way gets it wrong twice a year.

- [The five formats](#the-five-formats)
- [Which resource takes which format](#which-resource-takes-which-format)
- [An example of each format](#an-example-of-each-format)
- [Dates in the answers](#dates-in-the-answers)
- [Daylight saving time](#daylight-saving-time)

## The five formats

| Format | Looks like | Has an offset | Notes |
| ------ | ---------- | ------------- | ----- |
| **RFC 2822** | `Sun, 25 Oct 2026 00:00:00 +0300` | Yes, the last part: `+0300`, `-0500`, or `GMT` | The reference writes it as `EEE, d MMM yyyy HH:mm:ss Z`. |
| **ISO 8601** | `2025-01-06T10:30:00Z` | Yes: `Z` for UTC, or `+02:00` | Accepted by only one resource (`GET /administrators`). |
| **`yyyy-MM-dd`** | `2026-10-01` | No: a date only | Not accepted by the log resources. |
| **Timestamp** | `1790812800000` | Not needed: one exact moment | Milliseconds since 1 January 1970 UTC. A number in seconds is read as milliseconds, so it means a day in January 1970. |
| **`dd/MM/yyyy`** | `26/10/2026` | No: a date only | Day first. Used by one resource (`generateReport`). `yyyy-MM-dd` is refused there. |

## Which resource takes which format

These are all the date and time parameters of the two references.

| Resource | Parameters | Accepts (reference) | Tried on the lab |
| -------- | ---------- | ------------------- | ---------------- |
| `GET /logs/transfers` | `startTimeAfter`, `startTimeBefore`, `endTimeAfter`, `endTimeBefore` | RFC 2822 | RFC 2822 works. ISO 8601, `yyyy-MM-dd` and a timestamp are refused with 400 "Date should be in RFC2822 Format". |
| `GET /logs/audit` | `fromDate`, `endDate` | RFC 2822 | RFC 2822 works. `yyyy-MM-dd` is refused with 400. |
| `GET /logs/server` | `fromDate`, `endDate` | RFC 2822 | RFC 2822 works. |
| End User `GET /transfers` | `startTimeAfter`, `startTimeBefore`, `endTimeAfter`, `endTimeBefore` | RFC 2822 or a timestamp | RFC 2822 works. A timestamp in milliseconds and ISO 8601 are refused with 400. |
| `GET /administrators` | `apiKeys.createdAt`, `apiKeys.expiresAt`, `apiKeys.lastAccessedAt`, each with `.from` and `.to` | RFC 2822 or ISO 8601 | Both work. |
| `GET /accounts` | `lastModified`, `user.lastLogin`, `user.lastFailedAuth`, `user.lastFailedSshKeyAuth`, `user.passwordCredentials.lastPasswordChange`, each with `.from` and `.to` | RFC 2822, `yyyy-MM-dd` or a timestamp | All three work (tried on `lastModified.from`). |
| `GET /deniedUsers` | `blockedAt`, `blockedUntil`, each with `.from` and `.to` | RFC 2822, `yyyy-MM-dd` or a timestamp | `yyyy-MM-dd` works. |
| `GET /statisticsSummary/activeUsers` | `lastAccessTime`, `lastAdhocAccessTime`, each with `.from` and `.to` | RFC 2822, `yyyy-MM-dd` or a timestamp | `yyyy-MM-dd` works. |
| `GET /statisticsSummary/generateReport` | `startDate`, `endDate` | `dd/MM/yyyy` | `dd/MM/yyyy` works. `yyyy-MM-dd` is refused with 400. |

Every other resource of the two APIs has no date or time parameter.

If you are not sure, use RFC 2822: every resource above that takes a window of time accepts it, except `generateReport`, which takes dates only.

## An example of each format

Each example was run on the lab. The numbers in the answers are the lab's; yours will differ. The examples use `-G` and `--data-urlencode`: curl encodes
the text, which has spaces, slashes and a plus sign. Set `ST_SERVER`, `ST_PORT`, `ST_USER` and `ST_PASSWORD` first. The `Referer` header is sent with
every call.

### RFC 2822, with the offset

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
  --data-urlencode "startTimeAfter=Sun, 25 Oct 2026 00:00:00 +0300" \
  --data-urlencode "endTimeBefore=Mon, 26 Oct 2026 00:00:00 +0200" \
  --data-urlencode "limit=1" --data-urlencode "fields=id" -H "accept: application/json" -H "Referer: x"
```

The answer has `"resultSet": {"returnCount": 1, "totalCount": 2873}`: the transfers that started in that day. The two ends of the window have different offsets,
because the clocks changed that night. A window with `GMT` instead of an offset works too.

The same filter with another format is refused:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
  --data-urlencode "startTimeAfter=2026-10-25T00:00:00+03:00" -H "accept: application/json" -H "Referer: x"
```

The answer is 400, with "Invalid start after date: 2026-10-25T00:00:00+03:00. Date should be in RFC2822 Format".

### ISO 8601

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators" \
  --data-urlencode "apiKeys.createdAt.from=2025-01-06T10:30:00Z" -H "accept: application/json" -H "Referer: x"
```

The answer is 200, with the administrators that have an API key created from that moment on. `GET /administrators` also takes the RFC 2822 form of the same moment,
`Mon, 06 Jan 2025 10:30:00 +0000`.

### `yyyy-MM-dd`

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" \
  --data-urlencode "lastModified.from=2026-10-01" --data-urlencode "lastModified.to=2026-10-31" \
  --data-urlencode "fields=name" -H "accept: application/json" -H "Referer: x"
```

The answer is 200, with the accounts modified in October 2026. The value has no time and no offset: see
[Dates without an offset](#dates-without-an-offset).

### Timestamp

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" \
  --data-urlencode "lastModified.from=1790812800000" --data-urlencode "fields=name" -H "accept: application/json" -H "Referer: x"
```

`1790812800000` is 1 October 2026, 00:00 UTC, in **milliseconds**. The answer is the same accounts as with `lastModified.from=2026-10-01`. A number in seconds
(`1790812800`) is read as milliseconds, so it means a moment in January 1970 and the filter lets through every account that has a modification time. Most languages give you seconds: multiply by 1000.

### `dd/MM/yyyy`

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/statisticsSummary/generateReport" \
  --data-urlencode "startDate=23/10/2026" --data-urlencode "endDate=27/10/2026" -H "accept: application/json" -H "Referer: x"
```

The answer is a report with one entry for each day from the 23rd to the 27th, **including the end date**. Each entry is named by the start of its day, with the
offset of that moment:

```
"2026-10-23T00:00:00.000+03:00"
"2026-10-24T00:00:00.000+03:00"
"2026-10-25T00:00:00.000+03:00"
"2026-10-26T00:00:00.000+02:00"
"2026-10-27T00:00:00.000+02:00"
```

The same call with `startDate=2026-10-23` is refused with 400: "Date 2026-10-23 is not in correct format. The correct format is: dd/MM/yyyy."

## Dates in the answers

The answers use three forms. Do not expect them to look like what you sent.

| Where | Looks like |
| ----- | ---------- |
| Log and transfer lists: `startTime` | RFC 2822 with an offset: `Sun, 25 Oct 2026 15:53:45 +0200` |
| Fields such as `accountCreationDate`, and the transfer id's `mTransferStartTime` | A timestamp in milliseconds: `1787902411110` |
| End User `GET /serverTime`, and the entries and times of a `generateReport` answer | ISO 8601 with an offset: `2026-10-27T06:45:26.168+0200` (`serverTime`), `2026-10-26T00:00:00.000+02:00` (report) |

The offset in an answer is the offset of the server's time zone at that moment, so it changes when the clocks do.

## Daylight saving time

Twice a year, clocks change. One day has 23 hours, and one has 25. A script that works out "yesterday" as "now minus 86,400 seconds" is wrong on those days
and for a day or two after. It can count a transfer in the wrong day, or twice. The server is not the problem. The script is.

### What the server does with the offset

- In the RFC 2822 filters it was tried on (`/logs/transfers`), the server reads the offset you give. The same moment written as `+0300`, `+0200` or `+0000`
  gives the same result.
- If you write the same clock digits with another offset, the window moves to a different moment, and the result changes.

So where a resource takes a window of time, always send an explicit offset. Never send a time without one.

### The mistake to avoid

```
start = midnight_today - N * 86400        # wrong twice a year
end   = start + 86400
```

On the day the clocks go back, this puts a boundary at 23:00 or 01:00 instead of midnight. Every later day in the window moves by one hour as well. It applies to
the resources that take an offset (the RFC 2822 and ISO 8601 filters above). The scripts in this repository that had it counted billable transfers per day with
`GET /logs/transfers`. A timestamp is one exact moment, so it has no offset to get wrong. A date only (`yyyy-MM-dd`, `dd/MM/yyyy`) cannot make this mistake
either, because no time is sent.

### The right way: ask the date tool for each midnight

Ask the system for each midnight. Do not add seconds.

**Linux (GNU date):**

```bash
midnight_ago() { date -d "$1 days ago 00:00:00" +%s; }
START=$(midnight_ago 3)        # start of the day 3 days ago
END=$(midnight_ago 2)          # start of the next day
date -d "@${START}" -R         # Sun, 25 Oct 2026 00:00:00 +0300
```

**macOS (BSD date):**

```bash
midnight_ago() {               # N = -1 is tomorrow
  if [ "$1" -ge 0 ]; then date -v-"$1"d -v0H -v0M -v0S +%s; else date -v+"$((-$1))"d -v0H -v0M -v0S +%s; fi
}
date -r "${START}" -R
```

**Python:**

```python
from datetime import date, datetime, time, timedelta
from email.utils import format_datetime
from zoneinfo import ZoneInfo

tz = ZoneInfo("Europe/Sofia")                      # your time zone
def day_window(day: date):
    start = datetime.combine(day, time.min, tzinfo=tz)
    end = datetime.combine(day + timedelta(days=1), time.min, tzinfo=tz)
    return format_datetime(start), format_datetime(end)   # RFC 2822, with the offset

day_window(date(2026, 10, 25))
# ('Sun, 25 Oct 2026 00:00:00 +0300', 'Mon, 26 Oct 2026 00:00:00 +0200')
```

The start and end of that day use different offsets, and the window is correct. Send the values as `startTimeAfter` and `endTimeBefore`, as in the RFC 2822 example above.

### Dates without an offset

A date only (`yyyy-MM-dd`, `dd/MM/yyyy`) leaves the time zone to the server.

- **`generateReport` (`dd/MM/yyyy`).** Tried: the server cuts each day at midnight **in its own time zone**, and names the day with the offset of that midnight. In
  the example above, the 25th starts at `+03:00` and the 26th at `+02:00`: the clocks went back in between. So the days of this report are the server's days, not
  yours. If your time zone is not the server's, your own daily totals will not match it.
- **`yyyy-MM-dd` on `/accounts`, `/deniedUsers` and `/statisticsSummary/activeUsers`.** Not tried: this guide does not say which time zone the day is in. Use RFC 2822
  there if you need to be exact, and ask your support contact if you must use the date.

What this guide did not check: how many hours the report counts for the 25-hour day, and whether other reports of the product cut the day the same way.

### Other places it can hurt

- **Scheduled jobs.** A job set for 02:30 does not run on the night clocks go forward, because that time does not exist. It can run twice when clocks go back.
  Schedule important jobs outside the 01:00 to 04:00 window, or run the server and the job in UTC.
- **Reports "per day".** Decide which day you mean, the server's or yours, and say so in the report.
- **Comparing two days.** A day with 25 hours can have more transfers than normal. That is not an error.

### How to test your script without waiting for the date

Run it with a time zone whose clocks went back yesterday. Use a POSIX `TZ` rule with the day number of the year (here `J<day>`). It works from the
fourth day of the year on:

```bash
D=$((10#$(date +%j)))          # today's day of the year
TZ="EET-2EEST,J$(( D > 30 ? D - 30 : 1 ))/0,J$(( D - 1 ))/3" ./your_script.sh
```

Every boundary your script sends must still be a midnight (`00:00:00`).

### Checklist

- [ ] The format matches the resource: RFC 2822 for the log filters, `dd/MM/yyyy` for `generateReport`, a timestamp in milliseconds, not seconds.
- [ ] Every time sent to a resource that takes a window has an explicit offset (or is in UTC).
- [ ] Each midnight is asked of `date` or a time zone library, never worked out as N times 86,400 seconds.
- [ ] Scheduled jobs avoid the 01:00 to 04:00 window, or run in UTC.
- [ ] Reports say which time zone defines "a day".
- [ ] The script was tested with a changed-clock time zone.
