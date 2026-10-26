#!/usr/bin/env python3
"""
The failures of the online checks that are known, and why, so that a run is green when only those fail and red when
anything else does.

tests/online/known_failures.tsv has one line per known failing assertion:

    <check number or file name>  <TAB>  <text of the FAIL line>  <TAB>  <why: an issue id, or what has to be done>

    known_failures.py judge LIST CHECK OUTPUT STATE   what the check printed: `known` when it failed and every FAIL line
                                                      is in the list, `unknown` when one is not, `clean` with no FAIL line.
                                                      The check and the list lines that fired go to STATE.
    known_failures.py report LIST STATE               the list lines whose check ran and did not fail on them: a known
                                                      failure that is fixed, to be taken off the list. Prints them, exit 1.

A line of the list is matched by the text being inside a FAIL line ("  FAIL  label  got: ..."), so it is stable against
the numbers in `got`.
"""
import os
import re
import sys


def read_list(path):
    rows = []
    if not os.path.exists(path):
        return rows
    for line in open(path, encoding="utf-8"):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3 or not all(p.strip() for p in parts[:3]):
            raise SystemExit("known_failures.tsv: a line needs check, text and why, tab separated: %r" % line)
        rows.append((parts[0].strip(), parts[1].strip(), parts[2].strip()))
    return rows


def applies(key, check):
    return check == key or check.startswith(key + ".")


def judge(rows, check, output, state):
    fails = [l for l in output.splitlines() if re.match(r"^\s+FAIL\s", l)]
    mine = [r for r in rows if applies(r[0], check)]
    fired, unknown = set(), []
    for line in fails:
        hit = [r for r in mine if r[1] in line]
        if hit:
            fired.update(r[1] for r in hit)
        else:
            unknown.append(line)
    with open(state, "a", encoding="utf-8") as f:
        f.write("RAN\t%s\n" % check)
        for text in sorted(fired):
            f.write("FIRED\t%s\t%s\n" % (check, text))
    if not fails:
        return "clean"
    return "unknown" if unknown else "known"


def report(rows, state):
    ran, fired = set(), set()
    if os.path.exists(state):
        for line in open(state, encoding="utf-8"):
            p = line.rstrip("\n").split("\t")
            if p[0] == "RAN":
                ran.add(p[1])
            elif p[0] == "FIRED":
                fired.add((p[1], p[2]))
    gone = [r for r in rows if any(applies(r[0], c) for c in ran) and not any(applies(r[0], c) and (c, r[1]) in fired for c in ran)]
    for key, text, why in gone:
        print("%s: no longer fails on '%s' (%s)" % (key, text, why))
    return 1 if gone else 0


def main(argv):
    if len(argv) == 6 and argv[1] == "judge":
        rows = read_list(argv[2])
        print(judge(rows, argv[3], open(argv[4], encoding="utf-8", errors="replace").read(), argv[5]))
        return 0
    if len(argv) == 4 and argv[1] == "report":
        return report(read_list(argv[2]), argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
