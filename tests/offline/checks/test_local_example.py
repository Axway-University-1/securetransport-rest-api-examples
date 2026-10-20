#!/usr/bin/env python3
"""
tests/local.example is the committed starting point for tests/local, which git ignores. It must be possible to copy it
and use the copy. This does what the README says (mkdir tests/local; cp -n tests/local.example/* tests/local/) in a
throwaway folder and checks:

  - the three files are there, and the copy does not overwrite a file that already exists (cp -n);
  - the config has every key the online runner reads, and its safety switches say no, so a copy that was not edited
    reaches no server: the online runner refuses it and says which line to change;
  - blocked_terms.txt blocks nothing until a term is added;
  - no document or script still points at the old place of the example (tests/online/integration.conf.example).

Runs offline. Exit code 0 means clean.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
EXAMPLE = os.path.join(REPO, "tests", "local.example")
RUNNER = os.path.join(REPO, "tests", "online", "run_online.sh")

failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1


print("=== the files are there ===")
for name in ("README.md", "integration.conf", "blocked_terms.txt"):
    check("tests/local.example/%s exists" % name, os.path.isfile(os.path.join(EXAMPLE, name)))
check("the example config is not still in tests/online", not os.path.exists(os.path.join(REPO, "tests", "online", "integration.conf.example")))

conf_text = open(os.path.join(EXAMPLE, "integration.conf")).read()


def value(key, text=conf_text):
    m = re.search(r'^%s="([^"]*)"' % key, text, re.M)
    return m.group(1) if m else None


print("=== the config has what the runner reads, and is inert until edited ===")
for key in ("st_server", "st_port", "st_user", "st_password", "st_confirm_lab", "st_allow_writes", "st_object_prefix"):
    check("%s is set" % key, value(key) is not None)
check("st_confirm_lab is no: nothing runs until the person says the server is a lab", value("st_confirm_lab") == "no", value("st_confirm_lab"))
check("st_allow_writes is no", value("st_allow_writes") == "no", value("st_allow_writes"))
check("the password is a placeholder", value("st_password") == "change_me", value("st_password"))
check("the objects the checks make carry a prefix", bool(value("st_object_prefix")), value("st_object_prefix"))

print("=== blocked_terms.txt blocks nothing until a term is added ===")
terms = [l for l in open(os.path.join(EXAMPLE, "blocked_terms.txt")).read().split("\n") if l.strip() and not l.strip().startswith("#")]
check("every line is a comment or empty, so a copy adds no term to the hygiene check", terms == [], terms)

print("=== the copy the README describes ===")
with tempfile.TemporaryDirectory(prefix="local_example_") as work:
    local = os.path.join(work, "local")
    os.makedirs(local)
    mine = os.path.join(local, "integration.conf")
    with open(mine, "w") as f:
        f.write('st_server="mine"\n')
    # the README's command: cp -n tests/local.example/* tests/local/
    # cp -n answers "not overwritten" and exits 1 for a file that is in the way: that is what it is for
    subprocess.run("cp -n '%s'/* '%s'/" % (EXAMPLE, local), shell=True, stderr=subprocess.DEVNULL)
    check("the copy has all three files", sorted(os.listdir(local)) == ["README.md", "blocked_terms.txt", "integration.conf"], sorted(os.listdir(local)))
    check("cp -n kept the config that was already there", open(mine).read() == 'st_server="mine"\n')
    os.remove(mine)
    subprocess.run("cp -n '%s'/* '%s'/" % (EXAMPLE, local), shell=True, stderr=subprocess.DEVNULL)
    check("without one in the way, the config is the example", open(mine).read() == conf_text)
    # the online runner, pointed at the copy, as it stands
    out = subprocess.run(["bash", RUNNER], capture_output=True, text=True, timeout=60,
                         env=dict(os.environ, ST_INTEGRATION_CONF=mine))
    check("the online runner refuses a copy that was not edited (exit 1), before any call", out.returncode == 1 and "Refusing to run." in out.stdout,
          (out.returncode, out.stdout[-200:]))
    check("and says which line to change", 'st_confirm_lab="yes"' in out.stdout, out.stdout[-200:])

print("=== nothing points at the old place ===")
tracked = subprocess.run(["git", "-C", REPO, "ls-files", "-z"], capture_output=True, text=True).stdout.split("\0")
stale = []
for f in tracked:
    if not f or f.endswith((".jpg", ".png", ".gif")) or f == "tests/offline/checks/test_local_example.py":
        continue
    try:
        text = open(os.path.join(REPO, f)).read()
    except Exception:
        continue
    if "online/integration.conf.example" in text or re.search(r"[^/]integration\.conf\.example", text):
        stale.append(f)
check("no tracked file names integration.conf.example", stale == [], stale)

print()
if failed:
    print("test_local_example: FAIL (%d)" % failed)
    sys.exit(1)
print("test_local_example: PASS")
