#!/usr/bin/env python3
"""Features/Guidance/usage-and-billing-reporting.md: the sections and the statements that must stay, the python snippet on a sample report, and the
bash snippet that counts billable transfers per day (the date function, and the whole loop against the stub curl). The curl examples are run by
test_feature_guidance.py."""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
import guide_checks as g  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


NAME = "usage-and-billing-reporting.md"
text = g.read(NAME)
blocks = g.blocks(text)

for heading in ("## Summary", "## Active users", "## The usage report", "## Billable transfers in the log", "## Checklist", "## What was not checked"):
    check("the guide has the section %s" % heading, heading in text)
check("the sections come in this order: active users, the report, billable transfers",
      text.index("## Active users") < text.index("## The usage report") < text.index("## Billable transfers in the log"))
check("it links the time formats guide", "(time-formats.md)" in text and (g.GUIDANCE / "time-formats.md").exists())

# statements that must stay, because the lab showed them
for label, needle in (
        ("the list is kept by name, not by account", "kept by name, not by account"),
        ("a deleted account stays in the list", "A deleted account stays in the list"),
        ("the 60 days are marked as the owner's, not tried", "come from the product owner"),
        ("one page is 100 names, limit=0 does not list all", "and with `limit=0`, the answer had 100 names"),
        ("lastAccessTime has no offset", "with no offset"),
        ("the days of the report are the server's, named with their offset", "named by the start of its day in the server's time zone, with the offset"),
        ("the end date is included", "the end date is **included**"),
        ("the refusals of generateReport", "Incorrect date frame"),
        ("ST.Transfers is the billable count", "The number of **billable** transfers of the day"),
        ("the outbound counter is said not to be rebuilt", "Not rebuilt"),
        ("a report you generate by hand includes today", "A report you generate by hand includes today"),
        ("read totalCount, never returnCount", "Read `resultSet.totalCount`"),
        ("account= is the filter, accountName= is not", "`accountName=` is **not** a filter"),
        ("the three values of isBillable", "`isBillable` has three values"),
        ("the chain rule has its cases", "A **decompress** step keeps the chain"),
        ("what was not checked is listed", "The 60 days of the active users list")):
    check(label, needle in text, needle)

# the python snippet: a sample answer of generateReport
py = next(code for lang, code in blocks if lang == "python" and "def report_rows" in code)
ns = {}
exec(compile(py, "guide", "exec"), ns)
sample = {"report": {"2026-10-26T00:00:00.000+02:00": {"usage": {"ST.Transfers": 88, "ST.TransfersIn": 80, "ST.TransfersOut": 30, "ST.ActiveUsers": 0, "ST.Volume": 0}},
                     "2026-10-25T00:00:00.000+03:00": {"usage": {"ST.Transfers": 1282, "ST.TransfersIn": 774, "ST.TransfersOut": 1089, "ST.ActiveUsers": 0, "ST.Volume": 0}}}}
rows = ns["report_rows"](sample)
check("report_rows gives one row for each day, in order, with the total, in and out", rows == [("2026-10-25", 1282, 774, 1089), ("2026-10-26", 88, 80, 30)], rows)
check("the summary numbers in the text add up (1282 + 88 = 1370, 774 + 80 = 854, 1089 + 30 = 1119)", "1370" in text and "854" in text and "1119" in text
      and 1282 + 88 == 1370 and 774 + 80 == 854 and 1089 + 30 == 1119)

# the table of days: the report's total and the log's billable count are never more than 10 apart, in the guide's own numbers
table = re.findall(r"\| (\d+ Oct[^|]*) \| (\d+) / (\d+) / (\d+) \| (\d+) / (\d+) / (\d+) \| (\d+) \|", text)
check("the table of days has the six days and the day it was asked", len(table) == 7, len(table))
check("in that table the report's total is within 10 of the log's billable count, and in the log billable = billable in + billable out",
      all(abs(int(t[1]) - int(t[4])) <= 10 and int(t[4]) == int(t[5]) + int(t[7]) for t in table), table)

# the bash snippet: the date function, then the whole loop against the stub curl
loop = next(code for lang, code in blocks if lang == "bash" and "midnight_ago()" in code)
func = loop[:loop.index("for N in")]
script = func + 'for N in 4 3 2 1 0 -1; do midnight_ago "$N"; done\n'
r = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
lines = r.stdout.strip().splitlines()
check("midnight_ago gives six midnights, with an RFC 2822 offset", r.returncode == 0 and len(lines) == 6 and all(" 00:00:00 " in l for l in lines), (r.returncode, r.stdout, r.stderr))
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    json.dump({"resultSet": {"returnCount": 1, "totalCount": 7}, "result": []}, f)
r = g.run_curl(loop, body=f.name)
out = [l for l in r.stdout.splitlines() if l.strip()]
check("the loop prints one line for each of the four days, with the count it read (totalCount 7)", r.returncode == 0 and len(out) == 4 and all(l.endswith("  7") for l in out), (r.returncode, r.stdout, r.stderr[-300:]))
check("and each call asks for isBillable=true, the window and limit=1", r.stderr.count("isBillable=true") == 4 and r.stderr.count("limit=1") >= 4 and r.stderr.count("startTimeAfter=") == 4, r.stderr[-300:])
Path(f.name).unlink()
print("test_guidance_usage_and_billing_reporting: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
