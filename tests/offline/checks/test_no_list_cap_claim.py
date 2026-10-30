#!/usr/bin/env python3
"""No file of the repository says that a list is capped at 100. The default page is 100, and a larger limit is honoured (the Admin transfer log gave 1000, the End
User transfer list gave 105 for limit=500): a text that says "at most 100" or "never more than 100" teaches a client to stop reading too early."""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PATTERN = re.compile(r"at most 100\b|never sends more than 100|never more than 100|up to 100 (?:objects|entries|transfers)\b|is at most 100", re.I)
files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
hits = []
for name in files:
    if name.startswith("tests/") or not name.endswith((".md", ".sh", ".bat", ".py")):
        continue
    try:
        text = (ROOT / name).read_text(encoding="utf-8", errors="replace")
    except OSError:
        continue
    for n, line in enumerate(text.splitlines(), 1):
        if PATTERN.search(line):
            hits.append("%s:%d: %s" % (name, n, line.strip()[:100]))
print("  %s  no file says that a list is capped at 100" % ("FAIL" if hits else "PASS"))
for h in hits:
    print("        " + h)
sys.exit(1 if hits else 0)
