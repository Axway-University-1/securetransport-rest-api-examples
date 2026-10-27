#!/usr/bin/env python3
"""The curl examples of the guides in Features/Guidance/, with the answer each guide says they give.

    python3 tools/guide_examples.py               a table: every example, its method, its path, the documented answer, and why it is not run
    python3 tools/guide_examples.py time-formats  only the guides whose name has that word

Used by tests/online/checks/70.guides_examples.py, which runs the ones that only read against the lab and compares the status with the guide, so a guide that
went stale after a product change is found. An example is a ```bash block that STARTS with `curl`.

The documented answer is read from the text right after the block, up to the next example or the next heading:
  - a ```text block that starts with an HTTP status line ("HTTP/1.1 200 OK")  -> that status
  - a sentence with "answer", "answers", "answered", "returns", "refused", "status" or "HTTP" and a status of 2xx, 4xx or 5xx ("The answer is 200", "is answered 403",
    "refused with 401", "400, with ...")  -> the first such status
  - a ```text block that comes first and starts with { or [  -> "2xx" (the answer is shown, so the call worked), or "4xx" when it is an error body
    (validationErrors, an errors list, "Error validating request"); what the text says after it is about something else
  - nothing  -> "2xx", flagged "no documented status": not a failure, only a note.
"""
import os
import re
import shlex
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# ST_GUIDES_DIR points the tool at another folder of guides (a test of the check itself: a guide that says the wrong status)
GUIDANCE = Path(os.environ["ST_GUIDES_DIR"]) if os.environ.get("ST_GUIDES_DIR") else ROOT / "Features" / "Guidance"

STATUSES = {200, 201, 202, 204, 400, 401, 403, 404, 405, 409, 415, 500, 503}
TRIGGER = re.compile(r"\b(answer|answers|answered|returns|returned|refused|status|HTTP)\b", re.I)
# a number followed by what it counts ("200 accounts", "500 entries") is a count, not a status
COUNTED = r"\s+(?:accounts?|entries|entry|users?|items?|bytes|transfers?|files?|objects?|seconds?|names?|servers?|routes?|days?|hours?|rows?|ms)\b"
STATUS_TOKEN = re.compile(r"(?<![\w.,/])`?([1-5]\d\d)`?(?!\w|[.,]\d|" + COUNTED + ")")
# what the environment of the check provides: anything else in an example is a variable an earlier step set
ENV_ALLOWED = {"ST_SERVER", "ST_PORT", "ST_USER", "ST_PASSWORD", "ST_ENDUSER_PORT"}


class Example:
    def __init__(self, guide, heading, index, code, line):
        self.guide, self.heading, self.index, self.code, self.line = guide, heading, index, code, line
        self.method, self.path = method_and_path(code)
        self.documented, self.how = "2xx", "no documented status"

    def label(self):
        return "%s, under '%s', example %d (%s %s)" % (self.guide, self.heading, self.index, self.method, self.path)

    def __repr__(self):
        return "Example(%s)" % self.label()


def method_and_path(code):
    """(method, path after /api/v2.0 without the query) of the first curl of a block."""
    text = re.sub(r"\\\n", " ", code)
    try:
        tokens = shlex.split(text, posix=True)
    except ValueError:
        tokens = text.split()
    method, body, get_flag, head = None, False, False, False
    for i, t in enumerate(tokens):
        if t in ("-X", "--request") and i + 1 < len(tokens):
            method = tokens[i + 1].upper()
        elif t.startswith("-X") and len(t) > 2:
            method = t[2:].upper()
        elif t in ("-I", "--head") or (t.startswith("-") and not t.startswith("--") and "I" in t[1:] and t[1:].isalpha()):
            head = True
        elif t in ("-G", "--get") or (t.startswith("-") and not t.startswith("--") and "G" in t[1:] and t[1:].isalpha()):
            get_flag = True
        elif t in ("-d", "--data", "--data-raw", "--data-binary", "-F", "--form", "--form-string"):
            body = True
    if method is None:
        method = "HEAD" if head else "POST" if (body and not get_flag) else "GET"
    m = re.search(r"/api/v2\.0(/[^\s?\"']*)", text)
    return method, m.group(1) if m else "?"


def skip_reason(example):
    """Why the example is not run by the check against the lab; None when it is."""
    code = example.code
    if example.method not in ("GET", "HEAD"):
        return "writes: " + example.method
    if "ST_ENDUSER_PORT" in code:
        return "End User API: it needs an end user account"
    names = set(re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", code))
    # ${x:-default} is a name too
    extra = sorted(n for n in names if n not in ENV_ALLOWED)
    if extra:
        return "needs the earlier step (%s)" % ", ".join("$" + n for n in extra)
    if re.search(r"(-b|--cookie|-K|--config)\s+[^\s-]", code) or re.search(r"@[\w./-]+", code):
        return "needs the earlier step (a file)"
    return None


def documented_status(prose, text_block, text_first=False):
    """(status, how) from the text after an example. The status is a number ('200'), '2xx' or '4xx'.

    text_first: the ```text block came before any prose, so it is the answer of this example, and what the prose says after it is about something else."""
    if text_block:
        first = next((l for l in text_block.splitlines() if l.strip()), "")
        m = re.match(r"HTTP/\S+\s+(\d{3})", first.strip())
        if m:
            return m.group(1), "the answer is shown with its status line"
        if text_first:
            if re.search(r'"validationErrors"|"errors"\s*:|Error validating request|"message"\s*:\s*"(Unauthorized|Invalid)', text_block):
                return "4xx", "the answer shown is an error"
            if text_block.lstrip().startswith(("{", "[")):
                return "2xx", "the answer is shown"
            prose = ""
    # what is said in brackets is an aside, often about another call ("(denied users answers 405)")
    prose = re.sub(r"\([^()]*\)", " ", prose)
    sentences = re.split(r"(?<=[.!?:])\s+|\n\s*\n", prose)
    for s in sentences:
        if not TRIGGER.search(s):
            continue
        for m in STATUS_TOKEN.finditer(s):
            if int(m.group(1)) in STATUSES:
                return m.group(1), "the text says: " + s.strip()[:90]
    if text_block and text_block.lstrip().startswith(("{", "[")):
        return "2xx", "the answer is shown"
    return "2xx", "no documented status"


def parse(text, guide):
    """The curl examples of one guide, in order."""
    lines = text.split("\n")
    out, heading, i, count = [], "", 0, 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^```(\w*)\s*$", line)
        if m:
            lang, start = m.group(1), i
            j = i + 1
            while j < len(lines) and not re.match(r"^```\s*$", lines[j]):
                j += 1
            code = "\n".join(lines[i + 1:j]) + "\n"
            if lang == "bash" and code.lstrip().startswith("curl"):
                count += 1
                ex = Example(guide, heading or "(top)", count, code, start + 1)
                # the text after: prose up to the next fence or heading, and a ```text block that comes first
                k, prose, text_block, text_first = j + 1, [], None, False
                while k < len(lines) and len(prose) < 14:
                    l = lines[k]
                    if re.match(r"^#{1,6} ", l):
                        break
                    fm = re.match(r"^```(\w*)\s*$", l)
                    if fm:
                        if fm.group(1) in ("text", "json") and text_block is None and not "".join(prose).strip().endswith(("bash",)):
                            e = k + 1
                            while e < len(lines) and not re.match(r"^```\s*$", lines[e]):
                                e += 1
                            text_block = "\n".join(lines[k + 1:e])
                            text_first = not "".join(prose).strip()
                            k = e + 1
                            continue
                        break
                    prose.append(l)
                    k += 1
                ex.documented, ex.how = documented_status("\n".join(prose), text_block, text_first)
                out.append(ex)
            i = j + 1
            continue
        hm = re.match(r"^#{1,6} (.*)$", line)
        if hm:
            heading = hm.group(1).strip()
        i += 1
    return out


def guides():
    return sorted(p for p in GUIDANCE.glob("*.md") if p.name != "README.md")


def parse_all(word=None):
    result = []
    for p in guides():
        if word and word not in p.name:
            continue
        result.extend(parse(p.read_text(), p.name))
    return result


def main(argv):
    rows = parse_all(argv[1] if len(argv) > 1 else None)
    for e in rows:
        why = skip_reason(e)
        print("%-34s %-5s %-34s %-6s %s" % (e.guide[:34], e.method, e.path[:34], e.documented, ("not run: " + why) if why else "run"))
    print("\n%d example(s); %d would be run" % (len(rows), sum(1 for e in rows if not skip_reason(e))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
