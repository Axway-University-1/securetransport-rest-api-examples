#!/usr/bin/env python3
"""House rules every bash example has to follow, checked on all of them (Admin, End User, Use Cases, Features).

These came from reviewing the scripts by hand. A rule that a person had to point out is a rule a test now holds, so a
new script cannot repeat it and the person reads the scripts for what only a person can judge.

  1. Usage notation: every optional parameter has a bracket of its own, [A] [B], never [A [B]].
  2. The "Usage:" a script prints is the one in its header, the same parameters in the same order.
  3. A script whose header lists a required parameter, run without any, stops with exit 2 and a usage, and has sent
     nothing to the server. (Exit 2 is "wrong use"; 1 is "the server said no".)

  4. Without its settings file a script says to copy the example file, exits 1 and has sent nothing. (Tried with a dummy value for each
     required parameter: a script that stops at a parameter first, exit 2, is not counted as tried.)

Runs offline, with a stub curl, 8 scripts at a time. Exit 0 is clean. With --changed it checks only the scripts changed since the last commit (the quick run).
"""
import concurrent.futures, os, re, subprocess, sys, tempfile, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TESTS = ROOT / "tests" / "offline"
TREES = ["Admin/API 2.0/bash", "EndUser/API 2.0/bash", "EndUser/UseCases", "Admin/UseCases", "Features"]
NESTED = re.compile(r"\[[A-Za-z_]+ \[")
# scripts that are not examples to run on their own (helpers sourced by others)
HELPERS = {"lib.sh", "session.sh", "ensure_session.sh", "set_variables.local.sh", "set_variables.local.example.sh"}

problems = []


def bad(rule, f, msg):
    problems.append(f"rule {rule}: {f}: {msg}")


def scripts():
    out = subprocess.check_output(["git", "ls-files", "*.sh"], cwd=ROOT, text=True).splitlines()
    return [f for f in out if f.startswith(tuple(TREES)) and Path(f).name not in HELPERS and "/lib/" not in f]


def header_usage(text):
    """The first command line under '# Usage:' in the header, without the leading '# ./name.sh'."""
    m = re.search(r"^# Usage:\s*\n#\s+(\./\S+)(.*)$", text, re.M)
    return (m.group(1), m.group(2).strip()) if m else (None, "")


def required(params):
    """Parameters outside any bracket, in the header's usage text (an option such as --apply is not counted)."""
    flat = re.sub(r"\[[^\]]*\]", "", params)
    return [w for w in flat.split() if re.fullmatch(r"[A-Z][A-Z0-9_]+", w)]


work = Path(tempfile.mkdtemp(prefix="conv_", dir=os.environ.get("ST_TEST_OUTPUT") or None))
try:
    (work / "bin").mkdir()
    shutil.copy(TESTS / "lib" / "stub_curl", work / "bin" / "curl")
    os.chmod(work / "bin" / "curl", 0o755)
    shutil.copy(TESTS / "fixtures" / "set_variables.test.sh", work / "settings.sh")
    env = dict(os.environ, PATH=f"{work / 'bin'}:{os.environ['PATH']}", ST_ADMIN_LOCAL_VARIABLES=str(work / "settings.sh"),
               ST_ENDUSER_LOCAL_VARIABLES=str(work / "settings.sh"), STUB_CURL_STATUS="200")
    def check_one(f):
        """Problems of one script and how many of its two tries reached what they try: (problems, ran, tried)."""
        local, ran, tried = [], 0, 0

        def bad(rule, f, msg):
            local.append(f"rule {rule}: {f}: {msg}")
        text = (ROOT / f).read_text(errors="replace")
        name, params = header_usage(text)
        if NESTED.search(params):
            bad(1, f, f"nested brackets in the header usage: {params}")
        for m in re.finditer(r'Usage: (\./[^"\\\n]*)', text):
            printed = m.group(1).strip()
            if name and NESTED.search(printed):
                bad(1, f, f"nested brackets in the printed usage: {printed}")
            if name and params:
                p = re.sub(r"\s+\(.*$", "", printed)
                if not (p.startswith(f"{name} {params}") or f"{name} {params}".startswith(p)):
                    bad(2, f, f"printed usage '{printed}' differs from the header '{name} {params}'")
            break
        # 4: no settings file. A dummy value for each required parameter; the script may stop at one of them (exit 2) before it gets there
        env_missing = dict(env, ST_ADMIN_LOCAL_VARIABLES="/nonexistent/settings.sh", ST_ENDUSER_LOCAL_VARIABLES="/nonexistent/settings.sh")
        r = subprocess.run(["bash", Path(f).name] + ["x"] * len(required(params)), cwd=ROOT / Path(f).parent, env=env_missing, text=True,
                           input="", capture_output=True, timeout=60)
        out = r.stdout + r.stderr
        if r.returncode == 1 and ("set_variables" in out or "settings" in out):
            tried += 1
            if re.search(r"^(URL|METHOD):", out, re.M):
                bad(4, f, "it sent something to the server with no settings file")
        elif r.returncode == 0 and not re.search(r"^(URL|METHOD):", out, re.M) and "set_variables" in text:
            bad(4, f, "without its settings file it exits 0")
        elif re.search(r"^(URL|METHOD):", out, re.M):
            bad(4, f, "it called the server with no settings file (exit %s)" % r.returncode)
        if required(params):
            ran += 1
            r = subprocess.run(["bash", Path(f).name], cwd=ROOT / Path(f).parent, env=env, text=True, input="",
                               capture_output=True, timeout=60)
            out = r.stdout + r.stderr
            if r.returncode != 2:
                bad(3, f, f"run without its required {required(params)} it exits {r.returncode}, not 2")
            if "sage" not in out:
                bad(3, f, "and it prints no usage")
            if re.search(r"^(URL|METHOD):", out, re.M):
                bad(3, f, "and it already sent something to the server")
        return local, ran, tried

    todo = scripts()
    if "--changed" in sys.argv:
        # only the scripts changed since the last commit (and the new ones): the quick run before a commit
        changed = set(subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=ROOT, text=True).splitlines()) | \
            set(subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard"], cwd=ROOT, text=True).splitlines())
        todo = [f for f in todo if f in changed]
    ran = tried_settings = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for local, r_ran, r_tried in pool.map(check_one, todo):
            problems.extend(local)
            ran += r_ran
            tried_settings += r_tried
finally:
    shutil.rmtree(work, ignore_errors=True)

print(f"checked {len(todo)} bash scripts, {ran} of them run without their required parameters, {tried_settings} stopped at a missing settings file")
for p in problems:
    print("  FAIL  " + p)
print("# CLEAN" if not problems else f"# {len(problems)} problem(s)")
sys.exit(1 if problems else 0)
