#!/usr/bin/env python3
"""
tools/review_status.py keeps the list of files a person has read and confirmed, and
reports the ones that changed since. This runs it on a throwaway git repository: nothing
is checked at first, marking a file or a folder records it, an edit makes it "changed
since checked", marking again clears that, a change of line endings only does not count,
a deleted file is reported, un-marking removes it, and an ignored file is never listed.

Runs offline. Exit code 0 means clean.
"""
import contextlib
import io
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools"))
import review_status as rs  # noqa: E402

failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1


def write(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="") as f:
        f.write(text)


def run(root, *args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rs.main(["--root", root] + list(args))
    return out.getvalue()


with tempfile.TemporaryDirectory(prefix="review_status_") as root:
    subprocess.run(["git", "init", "-q", root], check=True)
    write(root, ".gitignore", "*.local.sh\n")
    write(root, "a.md", "one\n")
    write(root, "dir/b.md", "two\nlines\n")
    write(root, "dir/c.md", "three\n")
    write(root, "secret.local.sh", "password\n")

    un, ch, gone, nope = rs.status(root)
    check("nothing is checked at first", (un, ch, gone) == ([], [], []) and nope == [".gitignore", "a.md", "dir/b.md", "dir/c.md"], nope)
    check("an ignored file is never listed", "secret.local.sh" not in nope)

    run(root, "--mark", "a.md")
    un, ch, gone, nope = rs.status(root)
    check("marking a file records it", un == ["a.md"] and "a.md" not in nope, un)
    run(root, "--mark", "dir")
    un, _, _, nope = rs.status(root)
    check("marking a folder records every file in it", un == ["a.md", "dir/b.md", "dir/c.md"], un)
    check("the list file itself is not counted as a file to check", "review/checked.tsv" not in nope and os.path.exists(os.path.join(root, rs.LIST_FILE)))

    write(root, "a.md", "one, edited\n")
    un, ch, gone, _ = rs.status(root)
    check("an edit makes the file 'changed since checked', and the others stay checked", ch == ["a.md"] and un == ["dir/b.md", "dir/c.md"], (ch, un))
    check("the report says to read it again", "CHANGED since they were checked" in run(root) and "  a.md" in run(root))

    run(root, "--mark", "a.md")
    un, ch, _, _ = rs.status(root)
    check("marking it again clears it", ch == [] and "a.md" in un)

    write(root, "dir/b.md", "two\r\nlines\r\n")
    _, ch, _, _ = rs.status(root)
    check("a change of line endings only is not a change (a CRLF checkout on Linux)", ch == [], ch)

    os.remove(os.path.join(root, "dir", "c.md"))
    _, _, gone, _ = rs.status(root)
    check("a checked file that is gone is reported", gone == ["dir/c.md"], gone)

    run(root, "--unmark", "dir")
    un, ch, gone, _ = rs.status(root)
    check("un-marking a folder removes its files from the list, gone ones too", un == ["a.md"] and gone == [], (un, gone))

    try:
        run(root, "--mark", "no/such/file")
        refused = False
    except SystemExit:
        refused = True
    check("marking something that is not in the repository is refused", refused)

    run(root, "--mark", "review")
    check("the list file is kept by the tool: marking its folder marks nothing and raises no error",
          "review/checked.tsv" not in rs.read_list(root))
    _, ch, _, nope = rs.status(root)
    check("so it never shows up as changed or as unchecked", "review/checked.tsv" not in ch and "review/checked.tsv" not in nope)

    out = run(root, "--unchecked")
    check("--unchecked lists what is not checked yet", "Not checked yet" in out and "dir/b.md" in out, out)

print()
if failed:
    print("test_review_status: FAIL (%d)" % failed)
    sys.exit(1)
print("test_review_status: PASS")
