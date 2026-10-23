#!/usr/bin/env python3
"""Which offline and online checks mention a script: the map from a script to its tests.

    python3 tools/test_map.py                  every script, with its offline and online checks
    python3 tools/test_map.py enduser 04.File  only the scripts whose path contains all the words
    python3 tools/test_map.py --missing        scripts that no offline check or no online check mentions

A script counts as covered by a check when the check's file names it (by file name, e.g.
11.files_filepath_POST_md5.sh, or without the extension for its bat twin). The map is read
from the files each time, so it cannot go stale.
"""
import subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXT = {".sh", ".bat", ".py"}
SKIP = ("tests/", "tools/", ".claude/", "review/")


def tracked():
    out = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines()
    return [f for f in out if Path(f).suffix in EXT and not f.startswith(SKIP)]


def checks(sub):
    return sorted(str(p.relative_to(ROOT)) for p in (ROOT / sub).glob("*") if p.is_file() and p.suffix in {".sh", ".py"})


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    missing = "--missing" in sys.argv
    texts = {c: (ROOT / c).read_text(errors="replace") for c in checks("tests/offline/checks") + checks("tests/online/checks")}
    # a script is run by every check that names it, or names the folder's use-case runner that calls it
    rows = []
    for f in tracked():
        if args and not all(a.lower() in f.lower() for a in args):
            continue
        name = Path(f).name
        stem = Path(f).stem
        names = {name} if Path(f).suffix != ".bat" else {name, stem}
        hit = [c for c, t in texts.items() if any(n in t for n in names)]
        off = [c.split("/")[-1] for c in hit if "/offline/" in c]
        on = [c.split("/")[-1] for c in hit if "/online/" in c]
        rows.append((f, off, on))
    for f, off, on in rows:
        if missing and off and on:
            continue
        print(f)
        print("    offline: " + (", ".join(off) or "-"))
        print("    online:  " + (", ".join(on) or "-"))
    print(f"\n{len(rows)} scripts; {sum(1 for r in rows if not r[1])} without an offline check, "
          f"{sum(1 for r in rows if not r[2])} without an online check")


main()
