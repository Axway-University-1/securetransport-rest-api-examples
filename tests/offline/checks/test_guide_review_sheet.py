#!/usr/bin/env python3
"""tools/guide_review_sheet.py: the sheet it writes for a guide (claims, status codes, code blocks and whether a test runs them, words to
double check, a checklist), on a small made-up guide and on the real guides, and the table it prints for all of them."""
import contextlib
import io
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
import guide_review_sheet as grs  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


def run(*args):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = grs.main(list(args))
    return rc, buf.getvalue()


GUIDE = '''# A made-up guide

**For:** testers who read this.
**Checked on:** SecureTransport 5.5. Where the text says "tried", it was run here.

## Summary

This guide is made up. It has a few claims and a few code blocks.

## Claims

Tried: a rename of a missing file answered 403. We did not try the second case. The upload of a big file is not tried here.
A refused request was answered with 400 in some runs.

| Case | What the lab does |
| ---- | ----------------- |
| A wrong name | refused |
| A new name | works |
| An old name | see the reference |

## Examples

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/version" -H "Referer: x"
```

```python
print("made up first line")
```

```python
print("a block no test runs")
```

```text
HTTP 403
```

The code is in `tests/offline/lib/stub_curl`, and I wrote it.
'''

tmp = tempfile.mkdtemp(prefix="grs_")
guides = Path(tmp) / "guides"
tests = Path(tmp) / "tests"
out = Path(tmp) / "out"
guides.mkdir()
tests.mkdir()
(guides / "made-up.md").write_text(GUIDE)
(guides / "README.md").write_text("# not a guide\n")
(tests / "test_guidance_made_up.py").write_text('print("made up first line")\n')

rc, printed = run("--folder", str(guides), "--out", str(out), "--tests", str(tests))
sheet = (out / "made-up.md").read_text() if (out / "made-up.md").exists() else ""
check("it writes one sheet for the guide, and none for the README", rc == 0 and sorted(os.listdir(out)) == ["made-up.md"], os.listdir(out))
check("the sheet has the title, For and Checked on", "# Review sheet: A made-up guide" in sheet and "**For:** testers who read this." in sheet
      and "**Checked on:** SecureTransport 5.5." in sheet)
check("the sheet has the five sections", all(h in sheet for h in ("## 1. Claims about the product", "## 2. Status codes the text gives",
                                                                  "## 3. Code blocks", "## 4. To double check", "## 5. Checklist")))
check("a sentence that says tried is a claim that says tried", "| tried | Claims | Tried: a rename of a missing file answered 403." in sheet, sheet[:2000])
check("a sentence that says not tried is a claim that says not tried", "| not tried | Claims | The upload of a big file is not tried here." in sheet)
check("a table row that says works or refused is a claim", "| tried | Claims | A wrong name \\| refused |" in sheet and "| tried | Claims | A new name \\| works |" in sheet)
check("a row that says neither is not a claim", "An old name" not in sheet.split("## 2.")[0])
check("the For and Checked on lines are not claims", "Where the text says" not in sheet.split("## 2.")[0].split("## 1.")[1])
check("the status codes are listed with their sentence", "| 403 | Claims | Tried: a rename of a missing file answered 403." in sheet
      and "| 400 | Claims |" in sheet)
check("a curl block is run by the generic guide test", "run by test_feature_guidance.py (stand-in curl)" in sheet)
check("a block whose first line is in the guide's test is run by that test", "run by test_guidance_made_up.py" in sheet)
check("a block that no test has is said so", "not run by a test" in sheet.split("## 3.")[1])
check("an output block is not code", "output or data, not code" in sheet)
check("the words to double check are found: we, I, a path of this repository", all(w in sheet.split("## 4.")[1] for w in ("| we |", "| I |", "| a path of this repository |")))
check("the checklist is empty boxes", sheet.count("- [ ] ") == 6 and "- [x]" not in sheet)
check("the table of all guides has the guide, tried, not tried and blocks", "made-up.md" in printed and "Not tried" in printed and printed.count("\n") >= 4, printed)
check("a folder with no guide is a problem, not an empty run", run("--folder", str(Path(tmp) / "none"), "--out", str(out))[0] == 2)

# the real guides
real_out = Path(tmp) / "real"
rc, printed = run("--out", str(real_out))
names = sorted(p.name for p in (ROOT / "Features" / "Guidance").glob("*.md") if p.name != "README.md")
check("every real guide gets a sheet", rc == 0 and sorted(os.listdir(real_out)) == names, (sorted(os.listdir(real_out)), names))
for n in names:
    s = (real_out / n).read_text()
    check("%s: the sheet has all five sections and a checklist" % n, all(h in s for h in ("## 1. ", "## 2. ", "## 3. ", "## 4. ", "## 5. Checklist")) and "- [ ] Ready to publish." in s)
    check("%s: it is in the table of all guides" % n, n in printed)
import re  # noqa: E402
with_curl = [n for n in names if re.search(r"```bash\ncurl", (ROOT / "Features" / "Guidance" / n).read_text())]
check("the curl examples of the real guides are said to be run by the generic test", with_curl and all("run by test_feature_guidance.py" in (real_out / n).read_text()
      for n in with_curl), with_curl)
check("the table of all guides ends with a row for all of them", "\nAll " in printed)

import shutil  # noqa: E402
shutil.rmtree(tmp, ignore_errors=True)
print("test_guide_review_sheet: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
