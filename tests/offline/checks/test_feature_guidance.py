#!/usr/bin/env python3
"""Features/Guidance: every guide is listed in the folder's README and linked from Features/README.md, its links resolve, and the code in
the daylight saving guide runs (the python snippet, the date function of this platform, and the TZ rule for testing)."""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
G = ROOT / "Features" / "Guidance"
failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


readme = (G / "README.md").read_text()
guides = sorted(p.name for p in G.glob("*.md") if p.name != "README.md")
check("every guide is listed in the folder's README", all(g in readme for g in guides), guides)
check("Features/README.md points to the folder and to the guide", "Guidance/" in (ROOT / "Features" / "README.md").read_text()
      and "Guidance/daylight-saving-time.md" in (ROOT / "Features" / "README.md").read_text())
for md in [G / "README.md"] + [G / g for g in guides]:
    for target in re.findall(r"\]\(([^)#]+)(?:#[^)]*)?\)", md.read_text()):
        if not target.startswith(("http", "mailto")):
            check("%s: the link %s resolves" % (md.name, target), (md.parent / target).exists())
check("no guide carries an internal issue number", not any(re.search(r"\bRD-\d+\b", (G / g).read_text()) for g in guides))
check("each guide says who it is for and what it was checked on", all("**For:**" in (G / g).read_text() and "**Checked on:**" in (G / g).read_text() for g in guides))

text = (G / "daylight-saving-time.md").read_text()
blocks = re.findall(r"```(\w+)\n(.*?)```", text, re.S)

# the python snippet: the day the clocks go back has two offsets, and so does the day they go forward
py = next(b for lang, b in blocks if lang == "python")
ns = {}
code = py.split("day_window(date(2026, 10, 25))")[0]
try:
    exec(compile(code, "guide", "exec"), ns)
    from datetime import date
    a = ns["day_window"](date(2026, 10, 25))
    b = ns["day_window"](date(2027, 3, 28))
    check("python: the day clocks go back starts at +0300 and ends at +0200",
          a == ("Sun, 25 Oct 2026 00:00:00 +0300", "Mon, 26 Oct 2026 00:00:00 +0200"), a)
    check("python: the day clocks go forward starts at +0200 and ends at +0300", b == ("Sun, 28 Mar 2027 00:00:00 +0200", "Mon, 29 Mar 2027 00:00:00 +0300"), b)
except Exception as e:  # noqa: BLE001
    check("python: the snippet runs", False, e)

# the date function: BSD or GNU, whichever this machine has
bsd = subprocess.run("date -v-1d >/dev/null 2>&1", shell=True).returncode == 0
want = "-v-" if bsd else "-d \"$1 days ago"
func_block = next(b for lang, b in blocks if lang == "bash" and "midnight_ago()" in b and want in b)
func = re.search(r"midnight_ago\(\) \{.*?\n?\}", func_block, re.S).group(0)
# a time zone whose clocks went back yesterday, by the rule the guide gives for tests
doc_tz = next(l for l in next(b for lang, b in blocks if lang == "bash" and "J$(( D" in b).splitlines() if l.startswith("TZ="))
doc_tz = doc_tz.replace(" ./your_script.sh", "")
day = int(subprocess.check_output(["date", "+%j"], text=True).strip(), 10)
if day > 3:
    script = 'D=%d; %s; export TZ; %s\n' % (day, doc_tz, func)
    fmt = 'date -r "$S" -R' if bsd else 'date -d "@$S" -R'
    script += 'for N in 4 3 2 1 0 -1; do S=$(midnight_ago $N); %s; done\n' % fmt
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    lines = r.stdout.strip().splitlines()
    check("date: six boundaries, every one a midnight, in a time zone whose clocks went back yesterday",
          r.returncode == 0 and len(lines) == 6 and all(" 00:00:00 " in l for l in lines), (r.returncode, r.stdout, r.stderr))
    offsets = [l.split()[-1] for l in lines]
    check("date: the offset changes between the days (the test rule really changes the clocks)", len(set(offsets)) == 2, offsets)
else:
    print("  (the first days of the year: the TZ rule of the guide needs the fourth day, skipped)")
check("the guide shows how to send the offset (RFC 2822 with the Z part, encoded by curl) and which endpoints cannot carry one",
      "How to send the offset" in text and "--data-urlencode \"startTimeAfter=Sun, 25 Oct 2026 00:00:00 +0300\"" in text
      and "dd/MM/yyyy" in text and "**No.** A date has no offset." in text)
check("the checklist and the warning about 86,400 seconds are in the guide", "86,400" in text and "- [ ] Every time sent to the API" in text)
print("test_feature_guidance: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
