#!/usr/bin/env python3
"""
Bring the docs in line with the Admin folders on disk: the per-folder counts in
the README table, the folder list in tests/checks/check_docs_match_repo.py, and
the totals the knowledge pack cites.

    sync_docs.py                                       recount every row
    sync_docs.py 22.DeniedUsers "22. Denied Users" "`/deniedUsers`, ..."
                                                       also add a row for a new folder
    sync_docs.py --check                               report drift, change nothing

check_docs_match_repo.py fails the suite when these drift; this fixes them.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _repo import REPO  # noqa: E402

A, B = "Admin/API 2.0/bash", "Admin/API 2.0/bat"
HEADER = "| Topic | Endpoints | bash | bat |"
LAST_CHECK_ENTRY = '        ("90. End To End Acknowledgment", "90.EndToEndAcknowledgment")]'


def count(folder, ext):
    path = os.path.join(REPO, folder)
    return len([f for f in os.listdir(path) if f.endswith(ext)]) if os.path.isdir(path) else 0


def folder_for(label):
    number = label.split(".")[0]
    names = [d for d in os.listdir(os.path.join(REPO, A)) if d.split(".")[0] == number]
    return names[0] if len(names) == 1 else None


def main(argv):
    check = argv[:1] == ["--check"]
    new = argv if not check else []
    if new and len(new) != 3:
        sys.exit(__doc__)
    readme_path = os.path.join(REPO, "README.md")
    readme = open(readme_path).read()
    lines = readme.split("\n")
    start = lines.index(HEADER) + 2
    if new:
        folder, label, desc = new
        if not any(l.startswith("| %s |" % label) for l in lines):
            num = int(folder.split(".")[0])
            i = start
            while lines[i].startswith("| ") and int(re.match(r"\| (\d+)\.", lines[i]).group(1)) < num:
                i += 1
            lines.insert(i, "| %s | %s | 0 | 0 |" % (label, desc))
    i = start
    while i < len(lines) and lines[i].startswith("| "):
        cells = [c.strip() for c in lines[i].strip("|").split("|")]
        folder = folder_for(cells[0])
        if folder:
            cells[2], cells[3] = str(count(A + "/" + folder, ".sh")), str(count(B + "/" + folder, ".bat"))
            lines[i] = "| " + " | ".join(cells) + " |"
        i += 1
    changed = []
    if "\n".join(lines) != readme:
        changed.append("README.md")
        if not check:
            open(readme_path, "w").write("\n".join(lines))

    chk_path = os.path.join(REPO, "tests/checks/check_docs_match_repo.py")
    chk = open(chk_path).read()
    if new:
        entry = '("%s", "%s")' % (new[1], new[0])
        if entry not in chk:
            chk = chk.replace(LAST_CHECK_ENTRY, "        %s,\n%s" % (entry, LAST_CHECK_ENTRY))
            changed.append("check_docs_match_repo.py")
            if not check:
                open(chk_path, "w").write(chk)

    tracked = subprocess.run(["git", "-C", REPO, "ls-files", "--cached", "--others", "--exclude-standard"],
                             capture_output=True, text=True).stdout.split("\n")
    nb = len([f for f in tracked if re.match(r"Admin/API 2\.0/bash/[^/]+/.*\.sh$", f)])
    nt = len([f for f in tracked if re.match(r"Admin/API 2\.0/bat/[^/]+/.*\.bat$", f)])
    for rel in (".claude/skills/st-api-orientation/SKILL.md", ".claude/agents/st-api-expert.md"):
        path = os.path.join(REPO, rel)
        text = open(path).read()
        new_text = re.sub(r"\b\d+ curl examples", "%d curl examples" % nb, text)
        new_text = re.sub(r"\b\d+ of them, for Windows", "%d of them, for Windows" % nt, new_text)
        new_text = re.sub(r"\b\d+ bat examples for Windows", "%d bat examples for Windows" % nt, new_text)
        if new_text != text:
            changed.append(rel)
            if not check:
                open(path, "w").write(new_text)
    print("bash %d, bat %d; %s %s" % (nb, nt, "drift in" if check else "updated", ", ".join(changed) or "nothing"))
    sys.exit(1 if check and changed else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
