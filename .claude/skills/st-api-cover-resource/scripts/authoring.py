"""
Write Admin examples in the house style: the bash file from its parts, and the
bat twin with its header derived from the bash one, so the two never disagree.

    from authoring import write_sh, write_bat
    write_sh("22.DeniedUsers", "01.deniedUsers_GET.sh",
             description=["This script lists ... using the", "`/deniedUsers` endpoint."],
             usage=["./01.deniedUsers_GET.sh"],
             notes=["- Requires `jq`, which prints one name per line."],
             body=r'''
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" ...
    ''', main_url="deniedUsers")
    write_bat("22.DeniedUsers", "01.deniedUsers_GET.bat", body=r'''...''', main_url="deniedUsers")

Write the bash file first: write_bat reads its Description, Usage and Notes.
The header's Author defaults to git's user.name and Location to ST_LOCATION
(Sofia); set ST_AUTHOR or ST_LOCATION to change them. Created is today.
"""
import datetime
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _repo import BASH, BAT, REPO  # noqa: E402

RULE = "=" * 78


def _who():
    author = os.environ.get("ST_AUTHOR") or subprocess.run(
        ["git", "-C", REPO, "config", "user.name"], capture_output=True, text=True).stdout.strip()
    return author, os.environ.get("ST_LOCATION", "Sofia"), datetime.date.today().isoformat()


def write_sh(folder, name, description, usage, notes, body, main_url=None, root=BASH):
    """description, usage, notes: lists of lines without the leading '# '."""
    author, location, created = _who()
    lines = ["#!/bin/bash", "# " + RULE, "# Script Name: " + name, "# Author: " + author,
             "# Created: " + created, "# Location: " + location, "# " + RULE, "# Description:"]
    lines += [("# " + line).rstrip() for line in description]
    lines += ["#", "# Usage:"] + [("# " + line).rstrip() for line in usage]
    lines += ["#", "# Notes:", "# - Ensure that `set_variables.sh` is correctly configured and sourced."]
    lines += [("# " + line).rstrip() for line in notes]
    lines += ["# " + RULE, "",
              "#", "# Get the directory of this script, so that it can be run from any location", "#",
              'SCRIPT_DIR=$(dirname "$(realpath "$0")")', "",
              'source "${SCRIPT_DIR}/../set_variables.sh"', "",
              'REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"']
    if main_url:
        lines.append('MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/%s"' % main_url)
    path = os.path.join(root, folder, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n" + body.lstrip("\n"))
    os.chmod(path, 0o755)
    return path


def bat_header(folder, name, main_url=None, sh_root=BASH):
    """The bash twin's Description to Notes as REM lines, adapted to Windows."""
    lines = open(os.path.join(sh_root, folder, name[:-4] + ".sh")).read().split("\n")
    start = lines.index("# Description:")
    end = next(i for i in range(start, len(lines)) if lines[i].startswith("# ====="))
    doc = []
    for line in lines[start:end]:
        line = line.replace(".sh", ".bat")
        line = line.replace("`set_variables.bat` is correctly configured and sourced",
                            "set_variables.bat is correctly configured and called")
        line = re.sub(r"export ([A-Z_]+)='([^']*)'", r"SET \1=\2", line)
        line = line.replace("so export it first", "so set it first").replace("so export them first", "so set them first")
        m = re.match(r"# - Requires `jq`, which (.*)\.$", line)
        if m:
            verb = m.group(1)
            for a, b in (("prints", "print"), ("reads", "read"), ("builds", "build"), ("finds", "find"),
                         ("edits", "edit"), ("looks", "look"), ("URL-encodes", "URL-encode")):
                verb = verb.replace(a, b)
            line = "# - PowerShell is used to %s, in place of jq." % verb
        line = re.sub(r"^#(\s+)\./", r"#\1", line)
        doc.append("REM" + line[1:] if line.startswith("#") else line)
    author, location, created = _who()
    out = ["@echo off", "REM " + RULE, "REM Script Name: " + name, "REM Author: " + author,
           "REM Created: " + created, "REM Location: " + location, "REM " + RULE]
    out += doc
    out += ["REM " + RULE, "", "SETLOCAL", "", "CALL ..\\set_variables.bat", "",
            "set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT"]
    if main_url:
        out.append("SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/" + main_url)
    return "\n".join(out) + "\n"


def write_bat(folder, name, body, main_url=None, root=BAT, sh_root=BASH):
    path = os.path.join(root, folder, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(bat_header(folder, name, main_url, sh_root) + body.lstrip("\n"))
    return path
