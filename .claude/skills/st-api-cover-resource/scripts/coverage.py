#!/usr/bin/env python3
"""
Rough coverage of the Admin API reference by the bash examples, per tag, in
reference order. A HEURISTIC: an operation counts as covered when some script
uses its method and every literal segment of its path. It gives false positives
and false negatives (a script that builds the path from variables); read the
folder before trusting a number.

    coverage.py              one line per tag
    coverage.py deniedUsers  that tag's operations, each marked + or -
"""
import glob
import re
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _repo import BASH  # noqa: E402
import endpoint  # noqa: E402


def covered(path, method, scripts):
    literal = [s for s in path.strip("/").split("/") if not s.startswith("{")]
    for text in scripts.values():
        if method == "HEAD" and "--head" not in text:
            continue
        if method not in ("GET", "HEAD") and not re.search(r'(-X|--request)\s*"?%s\b' % method, text):
            continue
        if all(s in text for s in literal):
            return True
    return False


def main(argv):
    scripts = {f: open(f).read() for f in glob.glob(os.path.join(BASH, "*", "*.sh"))}
    ops = endpoint.operations()
    tags = endpoint.tag_order()
    for tag in (argv or tags):
        mine = [(p, m, s) for t, p, m, s in ops if t == tag]
        miss = [(p, m, s) for p, m, s in mine if not covered(p, m, scripts)]
        if argv:
            for p, m, s in mine:
                print("  %s %-7s %s - %s" % ("-" if (p, m, s) in miss else "+", m, p, s))
        else:
            print("%-26s %3d operations, ~%d not found in a script" % (tag, len(mine), len(miss)))


if __name__ == "__main__":
    main(sys.argv[1:])
