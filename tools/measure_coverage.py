#!/usr/bin/env python3
"""One report of how well the examples are tested, and how it moves from run to run.

    python3 tools/measure_coverage.py                      the report from what was measured before, plus the fast measures
    python3 tools/measure_coverage.py --offline            measure the offline suite again (it runs, with a tracer: as long as the suite)
    python3 tools/measure_coverage.py --online             measure the lab run (WRITES TO THE LAB: run_online.sh --write, about half an hour)
    python3 tools/measure_coverage.py --mutation S [S ...] break these scripts on purpose and see whether a check notices
                                                           (tools/mutation_probe.py; the results of earlier scripts are kept)
    python3 tools/measure_coverage.py --history            the rows of earlier reports

Five measures, each answering a question:

  1. API reach        Which operations of the reference (Admin and End User) does some example call?  (heuristic: method and the
                      literal parts of the path; the reference is in tests/local, so this needs it)
  2. Offline reach    Which examples does the offline suite run, and do the ones that talk to the server make a call in a test?
  3. Online reach     Which examples does a run against the lab run?
  4. Assertion depth  When an example is broken on purpose, does a check fail?  (the mutation score; only for the scripts probed so far)
  5. House rules      Do all bash examples follow the rules of check_script_conventions.py?

What is measured is kept in tests/local/coverage/ (git ignores it): state.json (each measure with its date), history.tsv (one row per
report, with the commit), report.md (the last report), and the traces. A measure that was not run this time is shown with the date it
was last measured, never silently as if it were fresh.

Exit code: 0 always for a report; 2 when asked to measure and it could not.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(os.environ["ST_COVERAGE_DIR"]) if os.environ.get("ST_COVERAGE_DIR") else ROOT / "tests" / "local" / "coverage"
SKILL = ROOT / ".claude" / "skills" / "st-api-cover-resource" / "scripts"
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(SKILL))
import script_coverage  # noqa: E402

# the tags the Admin reference has that the lab cannot show (CLAUDE.md: no Connect:Direct, standalone, no cluster)
ADMIN_BY_DESIGN = {"siteTemplates", "clusterServices"}


def today():
    return time.strftime("%Y-%m-%d")


def commit():
    try:
        return subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, text=True).strip()
    except Exception:  # noqa: BLE001
        return "?"


def load_state():
    p = OUT / "state.json"
    return json.loads(p.read_text()) if p.exists() else {}


def save_state(state):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "state.json").write_text(json.dumps(state, indent=1))


# --------------------------------------------------------------------------- 1. API reach
def api_reach():
    try:
        import coverage as cov
        import endpoint
    except Exception as e:  # noqa: BLE001
        return {"error": "the reference tools are not usable: %s" % e}
    result = {}
    for name, spec, folder, skip in (("admin", ROOT / "tests" / "local" / "admin20-spec", ROOT / "Admin" / "API 2.0" / "bash", ADMIN_BY_DESIGN),
                                     ("enduser", ROOT / "tests" / "local" / "enduser-spec", ROOT / "EndUser" / "API 2.0" / "bash", set())):
        if not (spec / "swagger.yaml").exists():
            result[name] = {"error": "no reference in %s (tests/st-api-cover-resource fetch_spec.sh)" % spec.relative_to(ROOT)}
            continue
        scripts = {f: open(f).read() for f in glob.glob(str(folder / "*" / "*.sh"))}
        ops = [o for o in endpoint.operations(str(spec)) if o[0] not in skip]
        miss = [(t, p, m) for t, p, m, _ in ops if not cov.covered(p, m, scripts)]
        result[name] = {"total": len(ops), "covered": len(ops) - len(miss), "missing": ["%s %s (%s)" % (m, p, t) for t, p, m in miss]}
    return result


# --------------------------------------------------------------------------- 2 and 3. execution reach
def execution(kind):
    log = OUT / ("%s.log" % kind)
    if not log.exists():
        return None
    r = script_coverage.analyse(log, online=(kind == "online"))
    out = {"total": r["total"], "run": r["total"] - len(r["missing"]), "missing": r["missing"]}
    if kind == "offline":
        out["with_calls"] = r["with_calls"]
        out["called"] = r["with_calls"] - len(r["silent"])
        out["silent"] = r["silent"]
    return out


def measure_execution(kind):
    OUT.mkdir(parents=True, exist_ok=True)
    log = OUT / ("%s.log" % kind)
    log.write_text("")
    script_coverage.record(log, online=(kind == "online"))
    return execution(kind)


# --------------------------------------------------------------------------- 4. assertion depth
def probe(scripts, per_operator, workers):
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / "mutation_last.json"
    cmd = [sys.executable, str(ROOT / "tools" / "mutation_probe.py")] + scripts + [
        "--per-operator", str(per_operator), "--workers", str(workers), "--json", str(tmp), "--report", str(OUT / "mutation_last.md")]
    rc = subprocess.run(cmd, cwd=ROOT).returncode
    if rc == 2 or not tmp.exists():
        return None
    return json.loads(tmp.read_text())


def merge_mutation(state, new):
    by = dict(state.get("mutation", {}).get("by_script", {}))
    for r in new["results"]:
        valid = [m for m in r["mutants"] if m["verdict"] != "invalid"]
        by[r["script"]] = {
            "made": new["made"], "valid": len(valid), "killed": sum(1 for m in valid if m["verdict"] == "killed"),
            "survivors": ["line %d, %s: %s  ->  %s" % (m["line"], m["operator"], m["before"][:90], m["after"][:90])
                          for m in valid if m["verdict"] == "survived"],
        }
    valid = sum(v["valid"] for v in by.values())
    killed = sum(v["killed"] for v in by.values())
    return {"by_script": by, "valid": valid, "killed": killed, "scripts": len(by)}


# --------------------------------------------------------------------------- 5. house rules
def house_rules():
    r = subprocess.run([sys.executable, str(ROOT / "tests" / "offline" / "checks" / "check_script_conventions.py")], capture_output=True, text=True)
    fails = [l.strip() for l in r.stdout.splitlines() if l.strip().startswith("FAIL")]
    m = re.search(r"checked (\d+) bash scripts", r.stdout)
    return {"scripts": int(m.group(1)) if m else None, "problems": fails}


# --------------------------------------------------------------------------- the report
def pct(a, b):
    return "n/a" if not b else "%d%%" % round(100 * a / b)


def fresh(entry, key="date"):
    return entry.get(key, "?") if entry else "never"


def build(state):
    total_scripts = len(script_coverage.tracked())
    L = ["# How well the examples are tested", "",
         "Report of %s, commit %s. %d bash and python examples are tracked. A measure shows the date it was last taken." % (today(), commit(), total_scripts), ""]
    rows = []

    api = state.get("api")
    L += ["## 1. API reach: operations of the reference that an example calls", ""]
    if not api:
        L.append("Not measured.\n")
    else:
        for name in ("admin", "enduser"):
            a = api["data"].get(name, {})
            if "error" in a:
                L.append("- %s: %s" % (name, a["error"]))
                rows.append("n/a")
            else:
                L.append("- **%s: %d of %d (%s)**" % (name, a["covered"], a["total"], pct(a["covered"], a["total"])))
                rows.append(pct(a["covered"], a["total"]))
                for m in a["missing"][:15]:
                    L.append("    - not called: %s" % m)
                if len(a["missing"]) > 15:
                    L.append("    - ... and %d more" % (len(a["missing"]) - 15))
        L.append("\n(measured %s. Admin leaves out %s: the lab cannot show them. A heuristic: method and the literal parts of the path.)\n" % (api["date"], ", ".join(sorted(ADMIN_BY_DESIGN))))
    if not api:
        rows += ["n/a", "n/a"]

    off = state.get("offline")
    L += ["## 2. Offline reach: examples the offline suite runs", ""]
    if not off:
        L.append("Not measured: run with --offline.\n")
        rows += ["n/a", "n/a"]
    else:
        d = off["data"]
        L.append("- **Run by a check: %d of %d (%s)**" % (d["run"], d["total"], pct(d["run"], d["total"])))
        L.append("- **Of the %d that talk to the server, %d make a call in a test (%s)**; the others only had their usage tried" % (d["with_calls"], d["called"], pct(d["called"], d["with_calls"])))
        for f in d["missing"][:15]:
            L.append("    - not run: %s" % f)
        for f in d["silent"][:15]:
            L.append("    - never calls the server in a test: %s" % f)
        L.append("\n(measured %s)\n" % off["date"])
        rows += [pct(d["run"], d["total"]), pct(d["called"], d["with_calls"])]

    on = state.get("online")
    L += ["## 3. Online reach: examples a run against the lab runs", ""]
    if not on:
        L.append("Not measured: run with --online (writes to the lab).\n")
        rows.append("n/a")
    else:
        d = on["data"]
        L.append("- **Run by an online check: %d of %d (%s)**" % (d["run"], d["total"], pct(d["run"], d["total"])))
        for f in d["missing"][:20]:
            L.append("    - not run: %s" % f)
        L.append("\n(measured %s. Left out: what is kept off the lab on purpose, see tools/test_map.py NO_ONLINE.)\n" % on["date"])
        rows.append(pct(d["run"], d["total"]))

    mu = state.get("mutation")
    L += ["## 4. Assertion depth: broken on purpose, does a check fail?", ""]
    if not mu:
        L.append("Not measured: run with --mutation SCRIPT ... (start with the scripts that make the most calls).\n")
        rows += ["n/a", "0"]
    else:
        L.append("- **Caught: %d of %d changes (%s), in %d script(s) probed of %d tracked**" % (mu["killed"], mu["valid"], pct(mu["killed"], mu["valid"]), mu["scripts"], total_scripts))
        for script, v in sorted(mu["by_script"].items(), key=lambda kv: kv[1]["killed"] / max(1, kv[1]["valid"])):
            L.append("    - %s: %d of %d caught (%s), %s" % (script, v["killed"], v["valid"], pct(v["killed"], v["valid"]), v["made"]))
            for s in v["survivors"][:6]:
                L.append("        - survived: %s" % s)
        L.append("\n(A survivor is a change no check noticed: a missing assertion, or a change nobody could see.)\n")
        rows += [pct(mu["killed"], mu["valid"]), str(mu["scripts"])]

    hr = state.get("rules")
    L += ["## 5. House rules", ""]
    if not hr:
        L.append("Not measured.\n")
        rows.append("n/a")
    else:
        d = hr["data"]
        L.append("- **%s**: %s bash scripts checked" % ("clean" if not d["problems"] else "%d problem(s)" % len(d["problems"]), d["scripts"]))
        for p in d["problems"][:15]:
            L.append("    - %s" % p)
        L.append("")
        rows.append("clean" if not d["problems"] else str(len(d["problems"])))
    return "\n".join(L), rows


def bar(value, width=10):
    """A bar for a share like '86%'; blank for n/a."""
    m = re.match(r"(\d+)%", value or "")
    if not m:
        return " " * width
    full = int(m.group(1)) * width // 100       # rounded down: 98% is not a full bar
    return "#" * full + "." * (width - full)


def delta(now, before):
    """Change in percentage points against the last report, as text."""
    a, b = re.match(r"(\d+)%", now or ""), re.match(r"(\d+)%", before or "")
    if not (a and b):
        return "" if now == before else "(new)" if before in (None, "", "n/a") else ""
    d = int(a.group(1)) - int(b.group(1))
    return "=" if d == 0 else "%+d pts" % d


def summary(state, rows, before_row):
    """The screen: a table of the measures (share, bar, what it is of, when measured, change), then where the gaps are."""
    def when(entry):
        if not entry:
            return "never"
        if "date" in entry:
            return entry["date"]
        dates = [v.get("made") for v in entry.get("by_script", {}).values() if v.get("made")]
        return max(dates) if dates else "?"      # mutation results carry the date of each script

    api, off, on, mu, hr = (state.get(k) for k in ("api", "offline", "online", "mutation", "rules"))
    ad, ed = (api or {}).get("data", {}).get("admin", {}), (api or {}).get("data", {}).get("enduser", {})
    od, nd, rd = (off or {}).get("data", {}), (on or {}).get("data", {}), (hr or {}).get("data", {})
    of = lambda a, b: "%d of %d" % (a, b)
    items = [
        ("API reach", "Admin operations an example calls", of(ad["covered"], ad["total"]) if "total" in ad else "no reference", when(api)),
        ("", "End User operations an example calls", of(ed["covered"], ed["total"]) if "total" in ed else "no reference", when(api)),
        ("Offline reach", "examples the offline suite runs", of(od["run"], od["total"]) if od else "", when(off)),
        ("", "...that make a call to the server in a test", of(od["called"], od["with_calls"]) if od else "", when(off)),
        ("Online reach", "examples a lab run runs", of(nd["run"], nd["total"]) if nd else "", when(on)),
        ("Assertion depth", "changes to a script that a check catches", of(mu["killed"], mu["valid"]) if mu else "", when(mu)),
        ("", "scripts probed so far", of(mu["scripts"], len(script_coverage.tracked())) if mu else "", when(mu)),
        ("House rules", "problems found in %s scripts" % (rd.get("scripts") or "?"), "none" if hr and not rd["problems"] else (str(len(rd["problems"])) if hr else ""), when(hr)),
    ]
    values = rows  # one value per item, in the order of HEADER[2:]
    before = before_row or [""] * (len(HEADER) - 2)
    table = []
    for (name, what, detail, measured), v, b in zip(items, values, before):
        table.append([name, what, v, bar(v) if v.endswith("%") else "", detail, measured, delta(v, b)])
    head = ["Measure", "What", "Result", "", "Of", "Measured", "Since last"]
    width = [max(len(str(r[i])) for r in table + [head]) for i in range(len(head))]
    line = lambda r: "  ".join(str(c).ljust(w) for c, w in zip(r, width)).rstrip()
    out = ["", line(head), "  ".join("-" * w for w in width)]
    last = None
    for r in table:
        if r[0] and last is not None:
            out.append("")
        out.append(line(r))
        last = r[0] or last
    out.append("")
    # where the gaps are: a few of each, the rest in the report
    gaps = []

    def gap(title, items, none="none"):
        if items:
            gaps.append("  %s (%d)" % (title, len(items)))
            gaps.extend("      %s" % i for i in items[:4])
            if len(items) > 4:
                gaps.append("      ... and %d more (report.md)" % (len(items) - 4))

    gap("Admin operations no example calls", ad.get("missing", []))
    gap("Examples the offline suite does not run", od.get("missing", []))
    gap("Examples that never call the server in a test", od.get("silent", []))
    gap("Examples no lab run runs", nd.get("missing", []))
    if mu:
        weak = sorted(mu["by_script"].items(), key=lambda kv: kv[1]["killed"] / max(1, kv[1]["valid"]))
        gap("Changes no check noticed, by script", ["%s: %d of %d caught" % (k.split("/")[-1], v["killed"], v["valid"]) for k, v in weak if v["survivors"]])
    gap("House rule problems", rd.get("problems", []))
    out.append("Where the gaps are" if gaps else "No gaps found.")
    out.extend(gaps)
    return "\n".join(out)


HEADER = ["date", "commit", "api_admin", "api_enduser", "offline_run", "offline_calls", "online_run", "mutation_caught", "mutation_scripts", "house_rules"]


def history_rows():
    p = OUT / "history.tsv"
    if not p.exists():
        return []
    return [l.split("\t") for l in p.read_text().splitlines()[1:] if l.strip()]


def print_history():
    rows = history_rows()
    if not rows:
        print("No report yet.")
        return
    widths = [max(len(h), *(len(r[i]) if i < len(r) else 0 for r in rows)) for i, h in enumerate(HEADER)]
    print("  ".join(h.ljust(w) for h, w in zip(HEADER, widths)))
    for r in rows:
        print("  ".join((r[i] if i < len(r) else "").ljust(w) for i, w in enumerate(widths)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--offline", action="store_true")
    ap.add_argument("--online", action="store_true")
    ap.add_argument("--mutation", nargs="+", metavar="SCRIPT")
    ap.add_argument("--per-operator", type=int, default=3)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--history", action="store_true")
    ap.add_argument("--full", action="store_true", help="print the whole report (it is always saved in report.md)")
    args = ap.parse_args()
    if args.history:
        print_history()
        return 0
    state = load_state()
    if args.offline:
        state["offline"] = {"date": today(), "data": measure_execution("offline")}
    if args.online:
        state["online"] = {"date": today(), "data": measure_execution("online")}
    if args.mutation:
        new = probe(args.mutation, args.per_operator, args.workers)
        if not new:
            print("the mutation probe could not run")
            return 2
        state["mutation"] = merge_mutation(state, new)
    elif "offline" not in state:
        data = execution("offline")
        if data:
            state["offline"] = {"date": "stored trace", "data": data}
    if "online" not in state:
        data = execution("online")
        if data:
            state["online"] = {"date": "stored trace", "data": data}
    state["api"] = {"date": today(), "data": api_reach()}
    state["rules"] = {"date": today(), "data": house_rules()}
    save_state(state)
    text, rows = build(state)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "report.md").write_text(text + "\n")
    hist = OUT / "history.tsv"
    before = history_rows()
    if not hist.exists():
        hist.write_text("\t".join(HEADER) + "\n")
    row = [today(), commit()] + rows
    # a report that shows what the last one showed (same commit, same numbers) is not a new row of the history
    if not (before and before[-1][1:] == row[1:] and before[-1][0] == row[0]):
        with open(hist, "a") as f:
            f.write("\t".join(row) + "\n")
    if args.full:
        print(text)
    print("HOW WELL THE EXAMPLES ARE TESTED   %s   commit %s   %d examples tracked" % (today(), commit(), len(script_coverage.tracked())))
    print(summary(state, rows, before[-1][2:] if before else None))
    print("\nDetail of every gap: %s   Earlier reports: python3 tools/measure_coverage.py --history" % (OUT / "report.md").relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
