#!/usr/bin/env python3
"""
Which files of this repository have been read and confirmed by a person, and which
have changed since.

Every file counts as NOT checked until it is marked. A marked file is recorded in
review/checked.tsv with the SHA-256 of its content (line endings normalised, so a CRLF
checkout does not look like a change) and the date. When it changes again it is listed
as "changed since checked", and is to be read again and marked again.

    python3 tools/review_status.py                  summary, and the files to read again
    python3 tools/review_status.py --unchecked      also list every file not checked yet
    python3 tools/review_status.py --mark PATH...   mark files, or every tracked file in a folder
    python3 tools/review_status.py --unmark PATH... take them off the list

Only files git tracks (or that are new and not ignored) are considered. Runs offline.
"""
import argparse
import datetime
import hashlib
import os
import subprocess
import sys

DEFAULT_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LIST_FILE = os.path.join("review", "checked.tsv")


def files_of(root):
    out = subprocess.run(["git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                         capture_output=True, text=True, check=True).stdout
    return sorted(p for p in out.split("\0") if p and os.path.isfile(os.path.join(root, p)))


def digest(root, rel):
    with open(os.path.join(root, rel), "rb") as f:
        data = f.read().replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def read_list(root):
    path = os.path.join(root, LIST_FILE)
    checked = {}
    if os.path.exists(path):
        for line in open(path).read().split("\n"):
            if line and not line.startswith("#"):
                rel, sha, day = line.split("\t")
                checked[rel] = (sha, day)
    return checked


def write_list(root, checked):
    path = os.path.join(root, LIST_FILE)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("# path<TAB>sha256 of the content when it was checked<TAB>date. Kept by tools/review_status.py: do not edit by hand.\n")
        for rel in sorted(checked):
            f.write("%s\t%s\t%s\n" % ((rel,) + checked[rel]))


def status(root):
    """(unchanged, changed, missing, unchecked): lists of paths."""
    checked, files = read_list(root), set(files_of(root))
    unchanged, changed, missing = [], [], []
    for rel, (sha, _day) in sorted(checked.items()):
        if rel not in files:
            missing.append(rel)
        elif digest(root, rel) == sha:
            unchanged.append(rel)
        else:
            changed.append(rel)
    unchecked = sorted(f for f in files if f not in checked and f != LIST_FILE)
    return unchanged, changed, missing, unchecked


def expand(root, paths):
    files = files_of(root)
    chosen = []
    for p in paths:
        rel = os.path.normpath(p).replace(os.sep, "/")
        hits = [f for f in files if f == rel or f.startswith(rel.rstrip("/") + "/")]
        if not hits:
            raise SystemExit("not a file or folder of this repository (a folder git ignores has nothing to mark): " + p)
        chosen.extend(hits)
    # The list is rewritten by every mark, so its own hash could never stay the same
    return sorted(set(chosen) - {LIST_FILE.replace(os.sep, "/")})


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=DEFAULT_ROOT, help="the repository (default: this one)")
    ap.add_argument("--mark", nargs="+", metavar="PATH")
    ap.add_argument("--unmark", nargs="+", metavar="PATH")
    ap.add_argument("--unchecked", action="store_true", help="also list the files not checked yet")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)

    if args.mark or args.unmark:
        checked = read_list(root)
        today = datetime.date.today().isoformat()
        for rel in expand(root, args.mark or []):
            checked[rel] = (digest(root, rel), today)
        for rel in args.unmark or []:
            prefix = os.path.normpath(rel).replace(os.sep, "/").rstrip("/")
            for key in [k for k in checked if k == prefix or k.startswith(prefix + "/")]:
                del checked[key]
        write_list(root, checked)

    unchanged, changed, missing, unchecked = status(root)
    print("checked and unchanged:     %d" % len(unchanged))
    print("changed since checked:     %d" % len(changed))
    print("checked, but gone:         %d" % len(missing))
    print("not checked yet:           %d" % len(unchecked))
    for title, items in (("CHANGED since they were checked: read again", changed), ("GONE (renamed or deleted): unmark or mark again", missing)):
        if items:
            print("\n" + title)
            for rel in items:
                print("  " + rel)
    if args.unchecked:
        print("\nNot checked yet")
        for rel in unchecked:
            print("  " + rel)
    return 0


if __name__ == "__main__":
    sys.exit(main())
