#!/usr/bin/env python3
"""Readability of the guides in Features/Guidance: short sentences, no filler, one name for one thing, a summary first.

The readers of the guides may not have English as a first language, so the prose is held to a few measurable rules. Prose means the text
outside code blocks, tables, headings and links' addresses. A word in backticks counts as one word.

  1. No sentence has more than 35 words (the hard limit).
  2. At most 3 percent of the sentences of a guide have more than 25 words. (After the readability pass of 27 October 2026 the guides have none, so
     3 percent leaves room for a few long sentences, such as a list of three names with codes, and no more.)
  3. No filler or hype phrase from a short list (BANNED below), and no em dash or en dash.
  4. The first section of detail is preceded by a summary: the guide opens with a "## Summary" with at least two sentences of prose.
  5. One name for one thing: a table of pairs where one form is preferred (TERMS below). The server's own words, in double quotes, are not checked.
  6. The words "the lab" are explained in the first block of the guide ("the test server that it was checked on"), except in the guide about testing,
     where "a lab" is something the reader sets up.

Runs offline. Exit 0 is clean.
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
GUIDES = sorted(p for p in glob.glob(os.path.join(ROOT, "Features", "Guidance", "*.md")) if not p.endswith("README.md"))

HARD_LIMIT = 35
LONG_LIMIT = 25
LONG_SHARE = 0.03

BANNED = ["it is important to note", "it's important to note", "worth noting", "in order to", "leverage", "utilize", "seamless", "robust",
          "delve", "comprehensive", "at the end of the day", "moving forward", "first and foremost", "needless to say", "in a nutshell",
          "rest assured", "game-changer", "cutting-edge", "holistic", "paradigm", "synergy", "pivotal", "crucial", "simply put",
          "it goes without saying", "when it comes to", "in terms of", "at its core", "state-of-the-art", "best-in-class"]

# preferred form -> the forms that must not appear (regular expressions, checked on prose with code and the server's own quoted words removed)
TERMS = {
    "End User API": r"\b(?:enduser|end user|End user|end-user|EndUser) API\b",
    "Admin API": r"\b(?:admin|Administration|administration|administrator) API\b",
    "SecureTransport": r"\bSecure Transport\b|\bSecuretransport\b",
    "login name": r"\busername\b|\buser name\b",
    "time zone": r"\btimezone\b|\btime-zone\b",
    "email": r"\be-mail\b|\bE-mail\b",
    "route (not flow)": r"\bflows?\b",
    "Basic authentication": r"\bbasic authentication\b|\bBasic auth\b|\bbasic auth\b",
    "API key": r"\bapi key\b|\bAPI-key\b|\bApi key\b",
    "RFC 2822": r"\bRFC2822\b|\bRFC-2822\b",
    "Expression Language": r"\bexpression language\b",
    "Transaction Manager": r"\btransaction manager\b",
}

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


def prose_paragraphs(text):
    """The paragraphs of prose: no code blocks, tables, headings or comments; a list item is a paragraph of its own."""
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    out, para = [], []

    def flush():
        if para:
            out.append(" ".join(para))
            para.clear()
    for line in text.split("\n"):
        s = line.strip()
        if not s:
            flush()
        elif s.startswith(("#", "|", "<!--")):
            flush()
        else:
            m = re.match(r"^(?:[-*]|\d+\.)\s+(.*)", s)
            if m:
                flush()
                para.append(re.sub(r"^\[[ x]\]\s*", "", m.group(1)))
            else:
                para.append(s)
    flush()
    return out


def clean(paragraph):
    p = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", paragraph)     # a link is its text
    p = re.sub(r"`[^`]*`", "CODE", p)                          # a word in backticks is one word
    return p.replace("**", "").replace("*", "")


def sentences(text):
    result = []
    for p in prose_paragraphs(text):
        for s in re.split(r"(?<=[.!?])\s+(?=[A-Z\"(])", clean(p)):
            if s.strip():
                result.append(s.strip())
    return result


def words(sentence):
    return len(sentence.split())


def own_words_removed(text):
    """Prose with the text in double quotes removed: the server's own words, a quotation, are not ours to rename."""
    return re.sub(r"\"[^\"]*\"", "", " ".join(clean(p) for p in prose_paragraphs(text)))


guides = {os.path.basename(p): open(p).read() for p in GUIDES}
check("there are guides to read", len(guides) >= 10, sorted(guides))

for name, text in guides.items():
    ss = sentences(text)
    over_hard = [s for s in ss if words(s) > HARD_LIMIT]
    over_long = [s for s in ss if words(s) > LONG_LIMIT]
    check("%s: no sentence above %d words" % (name, HARD_LIMIT), not over_hard, [s[:90] for s in over_hard[:3]])
    share = len(over_long) / max(1, len(ss))
    check("%s: at most %d%% of the %d sentences above %d words (now %d)" % (name, round(LONG_SHARE * 100), len(ss), LONG_LIMIT, len(over_long)),
          share <= LONG_SHARE, [s[:90] for s in over_long[:3]])
    lower = text.lower()
    found = [b for b in BANNED if b in lower]
    check("%s: no filler phrase, no em dash or en dash" % name, not found and "—" not in text and "–" not in text, found)

    # the summary comes first, and it is prose
    h2 = [m.group(1) for m in re.finditer(r"^## (.*)$", text, re.M)]
    first = text.split("\n## ", 1)[1].split("\n## ", 1)[0] if "\n## " in text else ""
    summary_sentences = sentences(first)
    check("%s: the first section is a Summary with at least two sentences of prose" % name,
          bool(h2) and h2[0] == "Summary" and len(summary_sentences) >= 2, (h2[:1], len(summary_sentences)))

    plain = own_words_removed(text)
    bad = {}
    for preferred, pattern in TERMS.items():
        hits = re.findall(pattern, plain)
        if hits:
            bad[preferred] = sorted(set(hits))
    check("%s: one name for one thing (%s)" % (name, ", ".join(sorted(TERMS))), not bad, bad)

    head = text.split("\n## ", 1)[0]
    if name != "testing-your-scripts.md" and "lab" in text.lower():
        check("%s: \"the lab\" is explained in the first block" % name, 'the lab" is the test server' in head, head[-200:])

# the checks work: a text that breaks each rule is caught (so that a pass above means something)
long_text = "Word " * 40 + "end."
check("the check sees a sentence above 35 words", len([s for s in sentences(long_text) if words(s) > HARD_LIMIT]) == 1)
check("the check counts a word in backticks as one word", words(clean("Send `a very long value with many words` now.")) == 3)
check("the check ignores code blocks and tables", sentences("```\n" + long_text + "\n```\n\n| a | " + long_text + " |\n") == [])
check("the check sees a variant of a name", re.search(TERMS["End User API"], "the enduser API answers") is not None
      and re.search(TERMS["End User API"], "the End User API answers") is None)
check("the server's own quoted words are not checked", "RFC2822" not in own_words_removed('It says "Date should be in RFC2822 Format" here.'))

print("test_guide_readability: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
