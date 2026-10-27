#!/usr/bin/env python3
"""A review sheet for each guide of Features/Guidance, for the person who must read a guide before it is published.

    python3 tools/guide_review_sheet.py                          every guide: one sheet each, and a table of all of them
    python3 tools/guide_review_sheet.py time-formats.md          one guide
    python3 tools/guide_review_sheet.py --folder DIR --out DIR   another folder of guides, another folder for the sheets

The sheets go to tests/local/guide_review/<guide>.md (git ignores tests/local). A sheet holds, taken from the guide by program:

  1. the title, For and Checked on;
  2. the claims about the product: (a) every sentence that says "tried", "verified", "not tried", "not checked" and so on, with its
     section and which of the two it says; (b) every table row whose last column says tried, not tried, works or refused; (c) every
     status code the text gives for a call, with the sentence;
  3. every code block: section, language, number of lines, the first line, and whether a test runs it (a `bash` block that starts with
     `curl` is run against a stand-in by tests/offline/checks/test_feature_guidance.py; another block counts as run when the guide's own test,
     tests/offline/checks/test_guidance_<name>.py, contains its first line; a block of a language the test reads by language is
     marked "probably run"; this part is a heuristic, read the test when it matters);
  4. the things to double check before the guide goes to a customer: "the lab", "we", "I", "our" and paths of this repository;
  5. an empty checklist to tick: facts read, examples tried by hand, wording, ready to publish.

It prints a table of all the guides: claims tried and not tried, code blocks, and blocks run by a test.

Nothing here talks to a server. The sheet says what the guide claims and how it is protected; it does not decide whether the claim is true.
"""
import argparse
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

NOT_TRIED = re.compile(r"\bnot (?:been )?(?:tried|re-?verified|checked)\b|\bwas not (?:tried|checked)\b|did not check|\bnot tried\b|reported[^.]*not tried", re.I)
TRIED = re.compile(r"\b(?:tried|verified|re-verified)\b", re.I)
CODE_WORDS = re.compile(r"(?:answers?|answered|refus(?:ed|es)|returns?|returned|gives?|gave|status|HTTP|code|codes|is|was|gets?|got|with|becomes?)"
                        r"\s+(?:a\s+|an\s+|the\s+)?(?:\*\*|`)?([2-5]\d\d)(?:\*\*|`)?(?!\d|[.,]\d)", re.I)
INTERNAL = [
    ("the lab", re.compile(r"\bthe lab\b", re.I)),
    ("we", re.compile(r"\b[Ww]e\b")),
    ("I", re.compile(r"\bI\b(?!/)")),
    ("our", re.compile(r"\b[Oo]ur\b")),
    ("a path of this repository", re.compile(r"(?:tests|tools|Admin|EndUser|Features|\.claude)/[\w./{}*-]+")),
]


def read_guide(path):
    return open(path, encoding="utf-8").read()


def title_for(text):
    for line in text.split("\n"):
        if line.startswith("# "):
            return line[2:].strip()
    return "(no title)"


def block_after(text, label):
    """The text of a header line such as '**For:** ...' and the lines that go on with it."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.startswith(label):
            out = [line[len(label):].strip()]
            j = i + 1
            while j < len(lines) and lines[j].strip() and not lines[j].startswith("**"):
                out.append(lines[j].strip())
                j += 1
            return " ".join(out)
    return "(missing)"


def clean(s):
    s = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", s)
    return s.replace("**", "")


def parse(text):
    """{'sentences': [(section, sentence)], 'rows': [(section, row)], 'blocks': [(section, language, code)]}"""
    sections = {"sentences": [], "rows": [], "blocks": []}
    heading = "(top)"
    in_code, lang, code = False, "", []
    para = []

    def flush():
        if para:
            p = clean(" ".join(para))
            para.clear()
            for s in re.split(r"(?<=[.!?])\s+(?=[A-Z\"(`])", p):
                if s.strip():
                    sections["sentences"].append((heading, s.strip()))
    for line in text.split("\n"):
        if line.strip().startswith("```"):
            if in_code:
                sections["blocks"].append((heading, lang, "\n".join(code)))
                in_code, lang, code = False, "", []
            else:
                flush()
                in_code, lang, code = True, line.strip()[3:].strip(), []
            continue
        if in_code:
            code.append(line)
            continue
        s = line.strip()
        m = re.match(r"^(#{1,6})\s+(.*)", s)
        if m:
            flush()
            heading = m.group(2).strip()
            continue
        if not s:
            flush()
        elif s.startswith("|"):
            flush()
            if not re.match(r"^\|[\s:|-]+\|?$", s):
                sections["rows"].append((heading, s))
        else:
            item = re.match(r"^(?:[-*]|\d+\.)\s+(.*)", s)
            if item:
                flush()
                para.append(re.sub(r"^\[[ x]\]\s*", "", item.group(1)))
            else:
                para.append(s)
    flush()
    return sections


def cells(row):
    return [c.strip() for c in row.strip().strip("|").split("|")]


def claim_kind(sentence):
    if NOT_TRIED.search(sentence):
        return "not tried"
    if TRIED.search(sentence):
        return "tried"
    return ""


def row_kind(row):
    last = cells(row)[-1] if cells(row) else ""
    if NOT_TRIED.search(last):
        return "not tried"
    if TRIED.search(last):
        return "tried"
    if re.search(r"\bworks?\b|\brefused\b|\bstored\b|\bAll three work\b", last, re.I):
        return "tried"
    return ""


def slug(guide_file):
    return os.path.splitext(os.path.basename(guide_file))[0].replace("-", "_")


def run_status(lang, code, guide_file, tests_dir, test_text):
    first = next((l.strip() for l in code.split("\n") if l.strip() and not l.strip().startswith("#")), "")
    if lang in ("", "text", "json", "console", "yaml", "http", "xml"):
        return "output or data, not code"
    if lang == "bash" and code.lstrip().startswith("curl"):
        return "run by test_feature_guidance.py (stand-in curl)"
    if test_text is None:
        return "not run by a test (no test file %s)" % ("test_guidance_%s.py" % slug(guide_file))
    if first and first in test_text:
        return "run by test_guidance_%s.py" % slug(guide_file)
    if re.search(r"""blocks\(.*\)|guide_checks""", test_text) and re.search(r"""["']%s["']""" % re.escape(lang), test_text):
        return "probably run by test_guidance_%s.py (it reads %s blocks)" % (slug(guide_file), lang)
    return "not run by a test"


def sheet_for(guide_file, tests_dir):
    text = read_guide(guide_file)
    parts = parse(text)
    test_path = os.path.join(tests_dir, "test_guidance_%s.py" % slug(guide_file))
    test_text = open(test_path, encoding="utf-8").read() if os.path.exists(test_path) else None
    name = os.path.basename(guide_file)

    claims = []          # (kind, where, text)
    title = title_for(text)
    for heading, s in parts["sentences"]:
        if heading == title:      # the For and Checked on lines under the title say how the guide was made, not what the product does
            continue
        k = claim_kind(s)
        if k:
            claims.append((k, heading, s))
    for heading, r in parts["rows"]:
        k = row_kind(r)
        if k:
            claims.append((k, heading, " | ".join(cells(r))))
    codes = []
    for heading, s in parts["sentences"]:
        for m in CODE_WORDS.finditer(s):
            codes.append((m.group(1), heading, s))
    for heading, r in parts["rows"]:
        for m in CODE_WORDS.finditer(r):
            codes.append((m.group(1), heading, " | ".join(cells(r))))
    blocks = []
    for heading, lang, code in parts["blocks"]:
        first = next((l.strip() for l in code.split("\n") if l.strip()), "")
        blocks.append((heading, lang or "(none)", len(code.split("\n")), first, run_status(lang, code, guide_file, tests_dir, test_text)))
    internal = []
    prose = [(h, s) for h, s in parts["sentences"]] + [(h, " ".join(cells(r))) for h, r in parts["rows"]]
    for label, rx in INTERNAL:
        hits = [(h, s) for h, s in prose if rx.search(re.sub(r"`[^`]*`", "", s) if label != "a path of this repository" else s)]
        if hits:
            internal.append((label, len(hits), hits[0]))

    def esc(s, n=170):
        s = s.replace("|", "\\|")
        return s if len(s) <= n else s[:n - 1] + "..."
    out = ["# Review sheet: %s" % title_for(text), "",
           "Guide: `%s`  " % name, "**For:** %s  " % block_after(text, "**For:**"), "**Checked on:** %s" % block_after(text, "**Checked on:**"), "",
           "Made by `tools/guide_review_sheet.py` from the guide. It lists what the guide claims and how that is protected. It does not say that a claim is true.", ""]
    tried = sum(1 for c in claims if c[0] == "tried")
    not_tried = sum(1 for c in claims if c[0] == "not tried")
    out += ["## At a glance", "",
            "| Claims that say tried | Claims that say not tried | Status codes given | Code blocks | Blocks run by a test |",
            "| --------------------- | ------------------------- | ------------------ | ----------- | -------------------- |",
            "| %d | %d | %d | %d | %d |" % (tried, not_tried, len(codes), len(blocks), sum(1 for b in blocks if b[4].startswith(("run", "probably")))), ""]
    out += ["## 1. Claims about the product", "",
            "Each line is a sentence or a table row that says it was tried, verified, not tried or not checked. Read them against the lab, or ask for the proof.", "",
            "| Says | Section | Claim |", "| ---- | ------- | ----- |"]
    out += ["| %s | %s | %s |" % (k, esc(h, 40), esc(t)) for k, h, t in claims] or ["| | | (none found) |"]
    out += ["", "## 2. Status codes the text gives", "", "| Code | Section | Where it is said |", "| ---- | ------- | ---------------- |"]
    out += ["| %s | %s | %s |" % (c, esc(h, 40), esc(t)) for c, h, t in codes] or ["| | | (none found) |"]
    out += ["", "## 3. Code blocks", "",
            "| Section | Language | Lines | First line | Run by a test |", "| ------- | -------- | ----- | ---------- | ------------- |"]
    out += ["| %s | %s | %d | `%s` | %s |" % (esc(h, 40), lang, n, esc(first, 60).replace("`", "'"), status) for h, lang, n, first, status in blocks] or ["| | | | | (none) |"]
    out += ["", "## 4. To double check before a customer reads it", "",
            "Words and paths that mean something to the team and may mean nothing to a customer. Decide for each: keep, explain, or change.", "",
            "| Item | Times | First place |", "| ---- | ----- | ----------- |"]
    out += ["| %s | %d | %s: %s |" % (label, n, esc(h, 30), esc(s, 110)) for label, n, (h, s) in internal] or ["| | | (none found) |"]
    out += ["", "## 5. Checklist", "",
            "- [ ] I read every claim in section 1 and I know where each one was tried.",
            "- [ ] I copied the examples (section 3) and tried them by hand.",
            "- [ ] The status codes in section 2 are what I see.",
            "- [ ] The items in section 4 are decided.",
            "- [ ] The wording is clear for a reader whose first language is not English.",
            "- [ ] Ready to publish.", ""]
    return "\n".join(out), {"name": name, "tried": tried, "not_tried": not_tried, "blocks": len(blocks),
                            "run": sum(1 for b in blocks if b[4].startswith(("run", "probably"))),
                            "code_blocks": sum(1 for b in blocks if not b[4].startswith("output"))}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("guides", nargs="*", help="guide file names (default: every guide of the folder)")
    ap.add_argument("--folder", default=os.path.join(ROOT, "Features", "Guidance"), help="the folder of guides")
    ap.add_argument("--out", default=os.path.join(ROOT, "tests", "local", "guide_review"), help="where the sheets go")
    ap.add_argument("--tests", default=os.path.join(ROOT, "tests", "offline", "checks"), help="the folder of the guides' tests")
    args = ap.parse_args(argv)
    files = [os.path.join(args.folder, g) for g in args.guides] if args.guides else \
        sorted(p for p in glob.glob(os.path.join(args.folder, "*.md")) if not p.endswith("README.md"))
    if not files:
        print("no guides in %s" % args.folder)
        return 2
    os.makedirs(args.out, exist_ok=True)
    rows = []
    for f in files:
        sheet, info = sheet_for(f, args.tests)
        with open(os.path.join(args.out, os.path.basename(f)), "w", encoding="utf-8") as fh:
            fh.write(sheet)
        rows.append(info)
    width = max(len(r["name"]) for r in rows)
    print("%-*s  %7s  %9s  %6s  %9s" % (width, "Guide", "Tried", "Not tried", "Blocks", "Run by a test"))
    print("%s  %s  %s  %s  %s" % ("-" * width, "-" * 7, "-" * 9, "-" * 6, "-" * 13))
    for r in rows:
        print("%-*s  %7d  %9d  %6d  %9d" % (width, r["name"], r["tried"], r["not_tried"], r["blocks"], r["run"]))
    print("%-*s  %7d  %9d  %6d  %9d" % (width, "All", sum(r["tried"] for r in rows), sum(r["not_tried"] for r in rows), sum(r["blocks"] for r in rows), sum(r["run"] for r in rows)))
    print("\nSheets: %s" % os.path.relpath(args.out, ROOT) if args.out.startswith(ROOT) else "\nSheets: %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
