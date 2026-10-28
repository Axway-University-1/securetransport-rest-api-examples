#!/usr/bin/env python3
"""Where a mutation run is: one line a person can read, from the progress file tools/mutation_probe.py writes.

    MUTATION_PROGRESS=/tmp/progress.jsonl python3 tools/mutation_probe.py SCRIPT ...     (or tools/measure_coverage.py --mutation ...)
    python3 tools/mutation_progress.py /tmp/progress.jsonl

It says: the script it is on (and which one of how many), the mutants done of the total, how many were caught, survived or did not parse, the time spent, and an estimate of the
time that is left (the mutants done so far set the pace, so the estimate is rough, and the first scripts are not typical of the last).
"""
import json
import sys
import time
from pathlib import Path


def summarize(lines, now=None):
    start = None
    script_no, current, per_script = 0, None, {}
    verdicts = {"killed": 0, "survived": 0, "invalid": 0}
    ended = False
    first_t = last_t = None
    for line in lines:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        first_t = first_t or e.get("t")
        last_t = e.get("t", last_t)
        if e["event"] == "start":
            start = e
        elif e["event"] == "script":
            script_no += 1
            current = e["script"]
            per_script[current] = {"total": e["mutants"], "done": 0}
        elif e["event"] == "mutant":
            verdicts[e["verdict"]] = verdicts.get(e["verdict"], 0) + 1
            if e["script"] in per_script:
                per_script[e["script"]]["done"] += 1
        elif e["event"] == "end":
            ended = True
    if not start:
        return "no run yet (the progress file is empty or has no start line)"
    done = sum(verdicts.values())
    total = start["mutants"]
    now = now or time.time()
    elapsed = max(0, (now if not ended else (last_t or now)) - (first_t or now))
    mins = lambda s: "%d min" % round(s / 60) if s >= 90 else "%d s" % s
    text = "%s: %d of %d mutants (%d%%); caught %d, survived %d, did not parse %d; %s spent" % (
        "FINISHED" if ended else "still running", done, total, round(100 * done / max(1, total)), verdicts["killed"], verdicts["survived"], verdicts["invalid"], mins(elapsed))
    if current and not ended:
        c = per_script[current]
        text += "; now on script %d of %d (%s, %d of %d mutants)" % (script_no, start["scripts"], Path(current).name, c["done"], c["total"])
    if not ended and done >= 10:
        text += "; about %s left" % mins(elapsed / done * (total - done))
    return text


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    p = Path(sys.argv[1])
    print(summarize(p.read_text().splitlines()) if p.exists() else "no progress file yet: " + str(p))
    return 0


if __name__ == "__main__":
    sys.exit(main())
