#!/usr/bin/env python3
"""tests/README.md: the section "Testing your own scripts" is there, and every tool and stand-in it names exists. The main README points to it."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
text = (ROOT / "tests" / "README.md").read_text(encoding="utf-8")
readme = (ROOT / "README.md").read_text(encoding="utf-8")
failed = []


def check(label, ok):
    print("  %s  %s" % ("PASS" if ok else "FAIL", label))
    if not ok:
        failed.append(label)


m = re.search(r"^## Testing your own scripts\n(.*?)(?=^##+ )", text, re.M | re.S)
check("tests/README.md has the section 'Testing your own scripts'", bool(m))
body = m.group(1) if m else ""
for path in ("offline/lib/stub_curl", "offline/lib/fake_requests", "tools/mutation_probe.py", "tools/script_coverage.py", "tools/measure_coverage.py"):
    on_disk = path if path.startswith("tools/") else "tests/" + path
    check("it names %s, which exists" % path, path in body and (ROOT / on_disk).exists())
for word in ("Referer", "Content-Type", "nothing", "mutation_probe", "put it back"):
    check("it says: %s" % word, word in body)
check("it is short (under 25 lines)", len(body.strip().splitlines()) < 25)
check("the main README has no such section any more, and points to this one", "### Testing your own scripts" not in readme and "tests/README.md#testing-your-own-scripts" in readme)
check("CONTRIBUTING.md points to it too", "tests/README.md#testing-your-own-scripts" in (ROOT / "CONTRIBUTING.md").read_text(encoding="utf-8"))
sys.exit(1 if failed else 0)
