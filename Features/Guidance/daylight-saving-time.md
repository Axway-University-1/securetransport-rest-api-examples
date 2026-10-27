# Daylight saving time and the SecureTransport REST API

**For:** administrators and integrators who script against the REST API or run scheduled jobs.
**Checked on:** SecureTransport 5.5-20260924. Where the text says "the server does", it was tried on this version only.

## Summary

Twice a year, clocks change. One day has 23 hours, and one has 25. A script that works out "yesterday" as "now minus 86,400 seconds" is wrong on
those days and for a day or two after. It can count a transfer in the wrong day, or twice. The server is not the problem. The script is.

## How to send the offset

The offset is the last part of the date text itself. The reference gives the format of most time filters as *RFC 2822*: `EEE, d MMM yyyy HH:mm:ss Z`.
The `Z` is the offset:

```
Sun, 25 Oct 2026 00:00:00 +0300
Sun, 25 Oct 2026 00:00:00 GMT
```

So the offset goes in the request, not only in the answer. With curl, let curl encode the text (it has spaces and a plus sign):

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
  --data-urlencode "startTimeAfter=Sun, 25 Oct 2026 00:00:00 +0300" \
  --data-urlencode "endTimeBefore=Mon, 26 Oct 2026 00:00:00 +0200" \
  --data-urlencode "limit=1" --data-urlencode "fields=id" -H "accept: application/json" -H "Referer: x"
```

Not every date parameter can carry an offset. These are all the date and time parameters the two references have, by what they accept:

| Where | Parameters | Accepts (reference) | Can carry an offset |
| ----- | ---------- | ------------------- | ------------------- |
| `GET /logs/transfers` | `startTimeAfter`, `startTimeBefore`, `endTimeAfter`, `endTimeBefore` | RFC 2822 | Yes. Tried: ISO 8601, `yyyy-MM-dd` and a timestamp are refused with 400 "Date should be in RFC2822 Format". |
| `GET /logs/audit`, `GET /logs/server` | `fromDate`, `endDate` | RFC 2822 | Yes (not tried here) |
| End User `GET /transfers` | `startTimeAfter`, `startTimeBefore`, `endTimeAfter`, `endTimeBefore` | RFC 2822 or a timestamp | Yes, in RFC 2822 (not tried here) |
| `GET /administrators` | `apiKeys.createdAt`, `.expiresAt`, `.lastAccessedAt`, each `.from` and `.to` | RFC 2822 or ISO 8601 | Yes (not tried here) |
| `GET /accounts` | `lastModified`, `user.lastLogin`, `user.lastFailedAuth`, `user.lastFailedSshKeyAuth`, `user.passwordCredentials.lastPasswordChange`, each `.from` and `.to` | RFC 2822, `yyyy-MM-dd` or a timestamp | Yes, in RFC 2822 (not tried here) |
| `GET /deniedUsers` | `blockedAt`, `blockedUntil`, each `.from` and `.to` | RFC 2822, `yyyy-MM-dd` or a timestamp | Yes, in RFC 2822 (not tried here) |
| `GET /statisticsSummary/activeUsers` | `lastAccessTime`, `lastAdhocAccessTime`, each `.from` and `.to` | RFC 2822, `yyyy-MM-dd` or a timestamp | Yes, in RFC 2822 (not tried here) |
| `GET /statisticsSummary/generateReport` | `startDate`, `endDate` | `dd/MM/yyyy` | **No.** A date has no offset. |

**What this guide is about.** It is about the first group: a window of time that you build in your script and send with an offset. That is where counting a
day as 86,400 seconds goes wrong. A **timestamp** is one exact moment, so it has no offset to get wrong (the day you took it from is still yours to compute).
Every other resource of the two APIs has no date or time parameter, and is not touched.

**What it is not about.** Where the parameter is a date only (`dd/MM/yyyy` in `generateReport`, `yyyy-MM-dd` in the others), your script cannot make that
mistake, because it sends no time. But the server then decides which time zone the day is in, and this guide does not say which, because it was not verified.
Use RFC 2822 wherever the endpoint accepts it, and ask your support contact for the others.

Answers carry an offset too, for example `Sun, 25 Oct 2026 15:53:45 +0200`. The End User `GET /serverTime` answers the server's time in ISO 8601 with its offset
from UTC.

## What the server does with the offset

- In the RFC 2822 filters it was tried on, the server reads the offset you give. The same moment written as `+0300`, `+0200` or `+0000` gives the same result.
- If you write the same clock digits with another offset, the window moves to a different moment, and the result changes.

So always send an explicit offset. Never send a time without one.

## The mistake to avoid

```
start = midnight_today - N * 86400        # wrong twice a year
end   = start + 86400
```

On the day the clocks go back, this puts a boundary at 23:00 or 01:00 instead of midnight. Every later day in the window moves by one hour as well.

## The right way: ask the date tool for each midnight

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

The start and end of that day use different offsets, and the window is correct.

Send the values as `startTimeAfter` and `endTimeBefore`, and let your HTTP client encode them (see the curl example above).

## Other places it can hurt

- **Scheduled jobs.** A job set for 02:30 does not run on the night clocks go forward, because that time does not exist. It can run twice when clocks
  go back. Schedule important jobs outside the 01:00 to 04:00 window, or run the server and the job in UTC.
- **Reports "per day".** Decide which day you mean, the server's or yours, and say so in the report. If the two are in different time zones, the daily
  totals will not match.
- **Comparing two days.** A day with 25 hours can have more transfers than normal. That is not an error.

## Usage and billing reports

`GET /statisticsSummary/generateReport` takes dates only (`dd/MM/yyyy`), so you cannot give it an offset. Ask your support contact which time zone the product uses to cut a day in it and in the usage reporting, and how a 23-hour or 25-hour day is shown. Check this
before you compare your own script's daily totals with a report. This guide does not say, because it was not verified.

## How to test your script without waiting for the date

Run it with a time zone whose clocks went back yesterday. Use a POSIX `TZ` rule with the day number of the year (here `J<day>`). It works from the
fourth day of the year on:

```bash
D=$((10#$(date +%j)))          # today's day of the year
TZ="EET-2EEST,J$(( D > 30 ? D - 30 : 1 ))/0,J$(( D - 1 ))/3" ./your_script.sh
```

Every boundary your script sends must still be a midnight (`00:00:00`).

## Checklist

- [ ] Every time sent to the API has an explicit offset (or is in UTC).
- [ ] Each midnight is asked of `date` or a time zone library, never worked out as N times 86,400 seconds.
- [ ] Scheduled jobs avoid the 01:00 to 04:00 window, or run in UTC.
- [ ] Reports say which time zone defines "a day".
- [ ] The script was tested with a changed-clock time zone.
