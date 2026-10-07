#!/usr/bin/env python3
"""
List every example script with what its header says, as JSON or as a table.

Other projects (the trainer kit, for one) build on this instead of parsing the
headers themselves, so the header format has one reader, tested here.

    python3 tools/list_examples.py            JSON, one object per bash example
    python3 tools/list_examples.py --table    a plain table: risk, path, endpoint

Each object:
    path         the bash example, relative to the repository root
    bat          its Windows twin, or null
    api          "admin", "enduser" or "feature"
    topic        the folder, e.g. "22.DeniedUsers"
    method       GET, HEAD, POST, PUT, PATCH or DELETE from the file name, or null
    endpoint     the first `/path` the Description names, or null
    risk         read | write | config | disruptive
    risk_note    the reason after the level, or ""
    description  the Description, as one line
    usage        the Usage lines

The risk levels:
    read        changes nothing on the server
    write       creates, changes or deletes objects (accounts, sites, routes...)
    config      changes a server-wide setting; put it back afterwards
    disruptive  stops a service, or cannot easily be undone: a demonstration only
"""
import glob
import json
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LEVELS = ("read", "write", "config", "disruptive")
PATTERNS = (("admin", "Admin/API 2.0/bash/*/*.sh"), ("enduser", "EndUser/API 2.0/bash/*/*.sh"), ("feature", "Features/*/*.sh"))
NOT_EXAMPLES = ("set_variables", "settings", "state")
METHOD = re.compile(r"_(GET|HEAD|POST|PUT|PATCH|DELETE)(_|\.|$)")
RISK = re.compile(r"^(?:#|REM) Risk: (\S+)(?: - (.*))?$", re.M)


def example_paths(repo=REPO):
    for api, pattern in PATTERNS:
        for path in sorted(glob.glob(os.path.join(repo, pattern))):
            if os.path.basename(path).startswith(NOT_EXAMPLES) or "/Features/lib/" in path:
                continue
            yield api, path


def twin(path):
    if "/bash/" in path:
        bat = path.replace("/bash/", "/bat/")[:-3] + ".bat"
    else:
        bat = path[:-3] + ".bat"
    return bat if os.path.exists(bat) else None


def risk_of(text):
    """(level, note) from the header's Risk line, or (None, "") when there is none."""
    found = RISK.findall(text)
    if len(found) != 1:
        return None, ""
    return found[0][0], found[0][1]


def section(lines, title):
    """The comment lines under '# Title:' up to the next blank '#' line."""
    out, inside = [], False
    for line in lines:
        if line.startswith("# %s:" % title):
            inside = True
            rest = line.split(":", 1)[1].strip()
            if rest:
                out.append(rest)
            continue
        if inside:
            if not line.startswith("#") or line.strip() == "#" or line.startswith("# ====="):
                break
            out.append(line[2:])
    return out


def describe(api, path, repo=REPO):
    text = open(path).read()
    lines = text.split("\n")
    level, note = risk_of(text)
    description = " ".join(s.strip() for s in section(lines, "Description"))
    endpoint = re.search(r"`(/[^`\s]*)`", description)
    method = METHOD.search(os.path.basename(path))
    bat = twin(path)
    return {
        "path": os.path.relpath(path, repo),
        "bat": os.path.relpath(bat, repo) if bat else None,
        "api": api,
        "topic": os.path.basename(os.path.dirname(path)),
        "method": method.group(1) if method else None,
        "endpoint": endpoint.group(1) if endpoint else None,
        "risk": level,
        "risk_note": note,
        "description": description,
        "usage": [s.strip() for s in section(lines, "Usage") if s.strip()],
    }


def examples(repo=REPO):
    return [describe(api, path, repo) for api, path in example_paths(repo)]


def main(argv):
    items = examples()
    if "--table" in argv:
        for e in items:
            print("%-10s %-75s %s" % (e["risk"], e["path"], e["endpoint"] or ""))
    else:
        json.dump(items, sys.stdout, indent=1)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
