#!/usr/bin/env python3
"""Does a test notice when a script is broken? Breaks a bash example on purpose, one small change at a time, runs the
offline checks that cover it, and lists the changes that no check noticed (the survivors).

    python3 tools/mutation_probe.py "Admin/API 2.0/bash/03.Connect/13.servers_operations_POST.sh" [SCRIPT ...]
    python3 tools/mutation_probe.py SCRIPT --per-operator 6 --workers 8 --report tests/local/mutation_13.md

A survivor is not always a bug in the tests: some changes do nothing a person could see (an equivalent mutant). Each one is
listed with its line, so a person can tell. What it never touches: your working tree (the mutants are made in scratch
copies of the tracked files), the lab, or the network (it runs only tests/offline).

The changes (operators), each applied at up to --per-operator places of the script, spread over it:
  method     the HTTP method of a call (POST becomes PUT, DELETE becomes GET ...)
  exit       a refusal that stops the script (exit 1, exit 2, return 1) that no longer stops it
  status     the status code the script waits for (200, 201, 204 becomes 299)
  header     a Content-Type or Referer header that is not sent
  url        a path segment of the URL that is wrong (an x added)
  key        a name in the body that is sent with another name
  compare    a comparison turned round (-eq / -ne, -gt / -le, -lt / -ge)
  output     a line the script prints, which is not printed (reported apart: a test may rightly not read every line)

Exit code: 0 when every mutant was caught, 1 when there are survivors, 2 for a problem with the run itself.
"""
import argparse
import concurrent.futures
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST_TIMEOUT = 600

METHOD_SWAP = {"POST": "PUT", "PUT": "POST", "PATCH": "PUT", "DELETE": "GET", "GET": "DELETE"}


def lines_of(text):
    return text.split("\n")


def is_code(line):
    s = line.strip()
    return bool(s) and not s.startswith("#")


def first_code_line(lines):
    """The header is the comment block on top: nothing in it is mutated."""
    for i, line in enumerate(lines):
        if i > 0 and is_code(line):
            return i
    return len(lines)


def sites(lines, operator):
    """(line index, new line) for every place the operator applies."""
    out = []
    start = first_code_line(lines)
    for i in range(start, len(lines)):
        line = lines[i]
        if not is_code(line):
            continue
        new = []
        if operator == "method":
            for m in re.finditer(r"-X (POST|PUT|PATCH|DELETE|GET)\b", line):
                new.append(line[:m.start()] + "-X " + METHOD_SWAP[m.group(1)] + line[m.end():])
        elif operator == "exit":
            for m in re.finditer(r"\b(exit [12]|return 1)\b", line):
                new.append(line[:m.start()] + ("exit 0" if m.group(1).startswith("exit") else "return 0") + line[m.end():])
        elif operator == "status":
            if re.search(r'"(?:200|201|204)"', line) and re.search(r"(?:\[|==|!=|=)", line):
                m = re.search(r'"(200|201|204)"', line)
                new.append(line[:m.start()] + '"299"' + line[m.end():])
        elif operator == "header":
            for m in re.finditer(r'-H "(?:Content-Type: [^"]*|\$\{REFERER_HEADER\}|Referer: [^"]*)"', line):
                new.append(line[:m.start()] + line[m.end():])
        elif operator == "url":
            m = re.search(r"(\$\{(?:MAIN_URL|ST_URL|BASE|SERVER_URL|URL)\}/|/api/v2\.0/)([A-Za-z])", line)
            if m:
                new.append(line[:m.end(1)] + "x" + line[m.end(1):])
        elif operator == "key":
            if re.search(r"jq |-d |\{", line):
                m = re.search(r'"([A-Za-z]{3,})":', line) or re.search(r"\{\s*([A-Za-z]{3,}):", line)
                if m:
                    new.append(line[:m.end(1)] + "X" + line[m.end(1):])
        elif operator == "compare":
            if re.match(r"\s*(if |\[|elif |while |.*&& \[|.*\|\| \[)", line) or "[ " in line:
                for a, b in ((" -eq ", " -ne "), (" -ne ", " -eq "), (" -gt ", " -le "), (" -lt ", " -ge "), (" -ge ", " -lt "), (" -le ", " -gt ")):
                    if a in line:
                        new.append(line.replace(a, b, 1))
                        break
        elif operator == "output":
            s = line.strip()
            if re.match(r"(printf|echo) ", s) and s.count('"') % 2 == 0 and not s.endswith("\\") and "<<" not in s and ">" not in s.split("printf")[-1][:3]:
                new.append("")
        for n in new:
            if n != line:
                out.append((i, n))
    return out


def spread(items, n):
    if len(items) <= n:
        return items
    step = len(items) / n
    return [items[int(k * step)] for k in range(n)]


def mutants(text, per_operator):
    lines = lines_of(text)
    result = []
    for operator in ("method", "exit", "status", "header", "url", "key", "compare", "output"):
        for i, new in spread(sites(lines, operator), per_operator):
            copy = list(lines)
            copy[i] = new
            result.append({"operator": operator, "line": i + 1, "before": lines[i].strip(), "after": new.strip() or "(line removed)",
                           "text": "\n".join(copy)})
    return result


def covering_tests(script):
    name = Path(script).name
    tests = []
    for p in sorted((ROOT / "tests" / "offline" / "checks").glob("test_*")):
        if p.suffix in {".sh", ".py"} and name in p.read_text(errors="replace"):
            tests.append(p.name)
    # the house rules apply to every bash example (a missing settings file, a missing parameter): last, since it is the slowest
    if (ROOT / "tests" / "offline" / "checks" / "check_script_conventions.py").exists():
        tests.append("check_script_conventions.py")
    return tests


def make_copy(dest):
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    for f in files:
        if not f or not (ROOT / f).is_file():
            continue
        target = Path(dest) / f
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / f, target)
    # some checks ask git which files are tracked: the copy is a repository of its own too
    subprocess.run(["git", "init", "-q"], cwd=dest, check=True)
    subprocess.run(["git", "add", "-A"], cwd=dest, check=True, capture_output=True)


def run_tests(copy, tests, limit=TEST_TIMEOUT):
    """(None when every test passed, else the name of the first one that failed; seconds the run took)."""
    began = time.time()
    for t in tests:
        path = Path(copy) / "tests" / "offline" / "checks" / t
        cmd = ["bash", str(path)] if t.endswith(".sh") else [sys.executable, str(path)]
        env = dict(os.environ, ST_TEST_OUTPUT=str(Path(copy) / "tests" / "offline" / "output"))
        p = subprocess.Popen(cmd, cwd=copy, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        try:
            rc = p.wait(timeout=limit)
        except subprocess.TimeoutExpired:
            # a mutant that never ends (a loop that no longer stops) is caught too: the whole process group goes
            os.killpg(p.pid, 9)
            p.wait()
            return t + " (hung: stopped after %d s)" % limit, time.time() - began
        if rc != 0:
            return t, time.time() - began
    return None, time.time() - began


def probe(script, args, pool_dirs):
    path = ROOT / script
    if not path.is_file() or path.suffix != ".sh":
        print("%s: not a tracked bash script, skipped" % script)
        return None
    original = path.read_text()
    tests = covering_tests(script)
    if tests == ["check_script_conventions.py"]:
        print("%s: no offline check names it, only the house rules cover it (a coverage gap): probing against those alone" % script)
    todo = mutants(original, args.per_operator)
    free = queue.Queue()
    for d in pool_dirs:
        free.put(d)
    mode = path.stat().st_mode

    def one(m):
        d = free.get()
        try:
            target = Path(d) / script
            target.write_text(m["text"])
            target.chmod(mode)
            syntax = subprocess.run(["bash", "-n", str(target)], capture_output=True)
            if syntax.returncode != 0:
                m["verdict"] = "invalid"
            else:
                failed, _ = run_tests(d, tests, limit)
                m["verdict"] = "killed" if failed else "survived"
                m["by"] = failed
            return m
        finally:
            (Path(d) / script).write_text(original)
            (Path(d) / script).chmod(mode)
            free.put(d)

    # the unmutated script must pass first: otherwise every mutant is "killed"
    base, took = run_tests(pool_dirs[0], tests)
    # a mutant gets 4 times as long as the checks need (and at least 30 s): longer than that, it is stuck
    limit = max(30, int(took * 4))
    if base:
        print("%s: the checks fail without any change (%s): fix that first" % (script, base))
        return "base"
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(pool_dirs)) as ex:
        done = list(ex.map(one, todo))
    return {"script": script, "tests": tests, "mutants": done}


def render(results):
    out = []
    for r in results:
        ms = r["mutants"]
        valid = [m for m in ms if m["verdict"] != "invalid"]
        killed = [m for m in valid if m["verdict"] == "killed"]
        core = [m for m in valid if m["operator"] != "output"]
        core_killed = [m for m in core if m["verdict"] == "killed"]
        out.append("## %s\n" % r["script"])
        out.append("Checks run: %s\n" % ", ".join(r["tests"]))
        pct = lambda a, b: ("%d%%" % round(100 * a / b)) if b else "n/a"
        out.append("Mutants: %d made, %d did not parse (not counted), %d counted. **Caught: %d of %d (%s)**; without the output lines: %d of %d (%s).\n"
                   % (len(ms), len(ms) - len(valid), len(valid), len(killed), len(valid), pct(len(killed), len(valid)),
                      len(core_killed), len(core), pct(len(core_killed), len(core))))
        by_op = {}
        for m in valid:
            by_op.setdefault(m["operator"], [0, 0])
            by_op[m["operator"]][1] += 1
            by_op[m["operator"]][0] += m["verdict"] == "killed"
        out.append("| change | caught | tried |\n|---|---|---|\n" + "\n".join("| %s | %d | %d |" % (k, v[0], v[1]) for k, v in by_op.items()) + "\n")
        survivors = [m for m in valid if m["verdict"] == "survived"]
        if survivors:
            out.append("Survivors (no check failed):\n")
            for m in survivors:
                out.append("- line %d, %s: `%s`  ->  `%s`" % (m["line"], m["operator"], m["before"][:140], m["after"][:140]))
            out.append("")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("scripts", nargs="+", help="repo-relative paths of bash examples")
    ap.add_argument("--per-operator", type=int, default=4)
    ap.add_argument("--workers", type=int, default=min(6, os.cpu_count() or 2))
    ap.add_argument("--report", help="also write the report to this file")
    ap.add_argument("--json", help="also write the results to this file, for tools/measure_coverage.py")
    args = ap.parse_args()
    work = tempfile.mkdtemp(prefix="mutation_")
    started = time.time()
    try:
        dirs = []
        for k in range(args.workers):
            d = os.path.join(work, "w%d" % k)
            make_copy(d)
            dirs.append(d)
        results = []
        for s in args.scripts:
            r = probe(s, args, dirs)
            if r == "base":
                return 2
            if r:
                results.append(r)
        text = render(results)
        print(text)
        print("(%d s)" % (time.time() - started))
        if args.report:
            Path(args.report).write_text(text + "\n")
        if args.json:
            import json
            slim = [{"script": r["script"], "tests": r["tests"],
                     "mutants": [{k: v for k, v in m.items() if k != "text"} for m in r["mutants"]]} for r in results]
            Path(args.json).write_text(json.dumps({"made": time.strftime("%Y-%m-%d"), "results": slim}, indent=1))
        survivors = sum(1 for r in results for m in r["mutants"] if m["verdict"] == "survived")
        return 1 if survivors else 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
