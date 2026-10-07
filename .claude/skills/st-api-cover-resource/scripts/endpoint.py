#!/usr/bin/env python3
"""
Print the reference for one or more endpoint paths, from the downloaded spec.

    endpoint.py /certificates "/certificates/{id}"     every operation under them
    endpoint.py --tags                                 the tags, in reference order
    endpoint.py --tag deniedUsers                      one tag's operations
    endpoint.py --index                                (re)write ops_by_tag.json

Schemas live in the other .yaml files next to swagger.yaml (configuration.yaml,
postExamples.yaml, ...); grep them for the names a $ref points at.
Run fetch_spec.sh first.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _repo import SPEC_DIR  # noqa: E402

METHODS = ("get", "post", "put", "patch", "delete", "head")


def paths_block(spec_dir=SPEC_DIR):
    lines = open(os.path.join(spec_dir, "swagger.yaml")).read().split("\n")
    return lines[lines.index("paths:") + 1:lines.index("components:")]


def operations(spec_dir=SPEC_DIR):
    """[(tag, path, METHOD, summary)] in reference order."""
    # The reference is not indented consistently (most methods at 4 spaces, some
    # at 6), so this keys on the structure, not on exact columns
    ops, path, method, tag, in_tags = [], None, None, None, False
    for line in paths_block(spec_dir):
        m = re.match(r"^  (/\S*):\s*$", line)
        if m:
            path, method = m.group(1), None
            continue
        m = re.match(r"^\s{4,6}(%s):\s*$" % "|".join(METHODS), line)
        if m:
            method, tag, in_tags = m.group(1).upper(), None, False
            continue
        if not method:
            continue
        if re.match(r"^\s+tags:\s*$", line):
            in_tags = True
            continue
        m = re.match(r"^\s+- (\S+)\s*$", line)
        if in_tags and tag is None and m:
            tag, in_tags = m.group(1), False
            continue
        m = re.match(r"^\s+summary:\s*(.*)$", line)
        if m:
            ops.append((tag, path, method, m.group(1).strip()))
            method = None
    return ops


def tag_order(spec_dir=SPEC_DIR):
    """The tags in the reference's own order, its top-level tags: list."""
    lines = open(os.path.join(spec_dir, "swagger.yaml")).read().split("\n")
    names = []
    if "tags:" in lines:
        for line in lines[lines.index("tags:") + 1:]:
            if line and not line.startswith(" "):
                break
            m = re.match(r"^  - name:\s*(\S+)", line)
            if m:
                names.append(m.group(1))
    seen = [t for t, _, _, _ in operations(spec_dir)]
    return names + [t for t in dict.fromkeys(seen) if t not in names]


def show(prefixes, spec_dir=SPEC_DIR):
    out, keep = [], False
    for line in paths_block(spec_dir):
        m = re.match(r"^  (/\S*):\s*$", line)
        if m:
            cur = m.group(1)
            keep = any(cur == p or cur.startswith(p + "/") for p in prefixes)
        if keep:
            out.append(line)
    return "\n".join(out)


def main(argv):
    if not os.path.exists(os.path.join(SPEC_DIR, "swagger.yaml")):
        sys.exit("No spec in %s; run fetch_spec.sh first." % SPEC_DIR)
    if argv[:1] == ["--index"]:
        ops = operations()
        tags = [t for t in tag_order() if any(tt == t for tt, _, _, _ in ops)]
        index = {"tags": tags, "by_tag": {t: [[p, m, s] for tt, p, m, s in ops if tt == t] for t in tags}}
        json.dump(index, open(os.path.join(SPEC_DIR, "ops_by_tag.json"), "w"), indent=1)
        print("%d operations, %d tags" % (len(ops), len(tags)))
    elif argv[:1] == ["--tags"]:
        for t in tag_order():
            print(t)
    elif argv[:1] == ["--tag"] and len(argv) == 2:
        for t, p, m, s in operations():
            if t == argv[1]:
                print("  %-7s %s - %s" % (m, p, s))
    elif argv:
        print(show(argv))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
