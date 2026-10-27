"""Helpers for the tests of the guides in Features/Guidance: read a guide, find its code blocks, and run a curl example against the stub curl.

    import guide_checks as g
    text = g.read("time-formats.md")
    for lang, code in g.blocks(text): ...
    r = g.run_curl(code)            # the stub answers; r.stderr has the METHOD:, URL:, HEADER: lines the call would send

A bash block that STARTS with `curl` is an example that is run by tests/offline/checks/test_feature_guidance.py (every guide), so it has to be
a complete command that works with ST_SERVER, ST_PORT, ST_USER and ST_PASSWORD set, and it has to send a Referer header (the stub refuses a call without one).
A block in another language (`text`, `json`, `console`) or one that starts with something else (a `#` comment, a variable) is not run.
"""
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GUIDANCE = ROOT / "Features" / "Guidance"
STUB = ROOT / "tests" / "offline" / "lib" / "stub_curl"


def read(name):
    return (GUIDANCE / name).read_text()


def guides():
    """The guides: every .md of the folder but its README."""
    return sorted(p.name for p in GUIDANCE.glob("*.md") if p.name != "README.md")


def blocks(text):
    """[(language, code)] of the fenced blocks."""
    return re.findall(r"```(\w*)\n(.*?)```", text, re.S)


def curl_examples(text):
    return [code for lang, code in blocks(text) if lang == "bash" and code.lstrip().startswith("curl")]


def run_curl(code, env=None, body=None):
    """Run a bash example with the stub curl first on PATH. `body` is a file whose text the stub answers to a GET."""
    d = tempfile.mkdtemp(prefix="guide_stub_")
    try:
        shutil.copy(STUB, os.path.join(d, "curl"))
        os.chmod(os.path.join(d, "curl"), 0o755)
        e = dict(os.environ, PATH=d + os.pathsep + os.environ["PATH"], ST_SERVER="st.example.com", ST_PORT="8444", ST_USER="u", ST_PASSWORD="p")
        if body:
            e["STUB_CURL_GET_BODY"] = body
        e.update(env or {})
        return subprocess.run(["bash", "-c", code], capture_output=True, text=True, env=e, timeout=60)
    finally:
        shutil.rmtree(d, ignore_errors=True)
