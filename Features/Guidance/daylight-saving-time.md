# Daylight saving time and the SecureTransport REST API

**For:** administrators and integrators who script against the REST API or run scheduled jobs.
**Checked on:** SecureTransport 5.5-20260924. Where the text says "the server does", it was tried on this version only.

## Summary

Twice a year, clocks change. One day has 23 hours, and one has 25. A script that works out "yesterday" as "now minus 86,400 seconds" is wrong on
those days and for a day or two after. It can count a transfer in the wrong day, or twice. The server is not the problem. The script is.

## What the server does

- When you send a time window, the server reads the time zone offset you give. The same moment written as `+0300`, `+0200` or `+0000` gives the
  same result.
- If you write the same clock digits with another offset, the window moves to a different moment, and the result changes.
- Times in answers carry an offset, for example `Sun, 25 Oct 2026 15:53:45 +0200`.

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

Send the values as `startTimeAfter` and `endTimeBefore`. Let your HTTP client encode them, for example with `curl -G --data-urlencode`.

## Other places it can hurt

- **Scheduled jobs.** A job set for 02:30 does not run on the night clocks go forward, because that time does not exist. It can run twice when clocks
  go back. Schedule important jobs outside the 01:00 to 04:00 window, or run the server and the job in UTC.
- **Reports "per day".** Decide which day you mean, the server's or yours, and say so in the report. If the two are in different time zones, the daily
  totals will not match.
- **Comparing two days.** A day with 25 hours can have more transfers than normal. That is not an error.

## Usage and billing reports

Ask your support contact which time zone the product uses to cut a day in usage reporting, and how a 23-hour or 25-hour day is shown. Check this
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
