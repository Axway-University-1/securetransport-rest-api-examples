#!/usr/bin/env python3
"""README.md: the section "Testing your own scripts" is there, and every tool and stand-in it names exists."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
text = (ROOT / "README.md").read_text(encoding="utf-8")
failed = []


def check(label, ok):
    print("  %s  %s" % ("PASS" if ok else "FAIL", label))
    if not ok:
        failed.append(label)


m = re.search(r"^### Testing your own scripts\n(.*?)(?=^##+ )", text, re.M | re.S)
check("the README has the section 'Testing your own scripts'", bool(m))
body = m.group(1) if m else ""
for path in ("tests/offline/lib/stub_curl", "tests/offline/lib/fake_requests", "tools/mutation_probe.py", "tools/script_coverage.py",
             "tools/measure_coverage.py", "tests/README.md"):
    check("it names %s, which exists" % path, path in body and (ROOT / path).exists())
for word in ("Referer", "Content-Type", "nothing", "mutation_probe", "put it back"):
    check("it says: %s" % word, word in body)
check("it is short (under 25 lines)", len(body.strip().splitlines()) < 25)
sys.exit(1 if failed else 0)
