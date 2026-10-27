#!/usr/bin/env python3
"""Features/Guidance/field-names-between-releases.md: the sections are there, the tables say what was tried, and the code in it runs
(first_field, version_key compared with the bash helper of Features/lib, the jq reader of a list that is a bare array or an object)."""
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
import guide_checks as g  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


text = g.read("field-names-between-releases.md")
heads = re.findall(r"^## (.+)$", text, re.M)
for h in ("Between releases", "The same thing, two names", "Two shapes for a list", "Names that are returned but cannot be asked for",
          "An answer that differs from the reference", "Write a client that survives", "Checklist"):
    check("section: %s" % h, h in heads, heads)
check("the table of releases marks what is reported and not tried", text.count("Reported") >= 3 and "reported, not tried on this release" in text)
for row in ("| File name | `filename` | `file` | `filename` |", "| Size | `filesize` | `size` | `filesize` |",
            "| Folder on the remote side | `remoteDir` | `remoteFolder` | `remoteDir` |", "`transferType`: `User upload`, `User download`", "`incoming`: `true`, `false`"):
    check("the transfer names: %s" % row[:60], row in text)
check("the shared names of the End User list and single object are counted (19, 38, 10)", "19 and 38 names" in text and "only 10 of them" in text)
check("the protocol/type refusal and the End User fields= are said", "Field protocol does not exist." in text and "Field type does not exist." in text and "was **not refused**" in text)
check("the daemon answer is said to be a bare list, and read both ways", "the answer to a **daemon operation** is a bare list" in text and 'type == "array"' in text)
check("the End User API is said to have no /version (404)", "answered 404" in text)

blocks = g.blocks(text)
# first_field and version_key, run
ns = {}
for lang, code in blocks:
    if lang == "python":
        exec(compile(code.split("\nme = first_field")[0] if "first_field(obj" in code else code, "guide", "exec"), ns)
ff, vk = ns["first_field"], ns["version_key"]
check("first_field: the first name that exists wins", ff({"name": "a", "loginName": "b"}, "loginName", "name") == "b" and ff({"name": "a"}, "loginName", "name") == "a")
try:
    ff({"x": 1, "y": 2}, "loginName", "name")
    check("first_field: a missing field says which names the object has", False)
except KeyError as e:
    check("first_field: a missing field says which names the object has", "x, y" in str(e) and "loginName, name" in str(e), str(e))
check("version_key: a dated update is newer than the base release", vk("5.5-20260924") > vk("5.5"))
check("version_key: dates and releases order correctly", vk("5.5-20260827") < vk("5.5-20260924") < vk("5.6") < vk("6.0-20250101"))
check("version_key: a date with only the month counts as the start of that month", vk("5.5-202609") == (5, 5, 20260900) and vk("5.5-202609") < vk("5.5-20260924"))
try:
    vk("hello")
    check("version_key: a text that is no version is refused", False)
except ValueError:
    check("version_key: a text that is no version is refused", True)
# the same order as the bash helper the guide names
helper = (g.ROOT / "Features" / "lib" / "st_feature_check.sh").read_text()
fn = re.search(r"st_version_key\(\) \{.*?\n\}\n", helper, re.S).group(0)
pairs = [("5.5", "5.5-20260924"), ("5.5-20260827", "5.5-20260924"), ("5.5-20260924", "5.6"), ("5.5-202609", "5.5-20260924"), ("5.10", "5.9")]
for a, b in pairs:
    out = subprocess.run(["bash", "-c", fn + 'a=$(st_version_key "%s"); b=$(st_version_key "%s"); [[ "$a" < "$b" ]] && echo less || echo notless' % (a, b)], capture_output=True, text=True).stdout.strip()
    check("python and bash agree that %s < %s (bash says %s)" % (a, b, out), (vk(a) < vk(b)) == (out == "less"), out)

# the jq reader, with an array and with an object
jq = next(code for lang, code in blocks if lang == "bash" and code.startswith("jq -r"))
arr = '[{"daemon":"FTP","message":"Daemon FTP is stopped.","isSuccessful":true}]'
obj = '{"daemonOperationResults":[{"daemon":"SSH","message":"Stopped.","isSuccessful":false}]}'
for label, body, want in (("a bare list", arr, "FTP Daemon FTP is stopped. (successful: true)"), ("an object", obj, "SSH Stopped. (successful: false)")):
    r = subprocess.run(["bash", "-c", "printf '%s' '" + body + "' | " + jq.strip()], capture_output=True, text=True)
    check("the jq reader reads %s" % label, r.stdout.strip() == want, (r.stdout, r.stderr))
print("test_guidance_field_names_between_releases: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
