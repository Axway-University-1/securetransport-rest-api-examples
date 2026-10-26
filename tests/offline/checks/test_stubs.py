#!/usr/bin/env python3
"""The stub curl of the offline tests: a call with no Referer header is an error (so a script that stops sending it fails every test that
runs it), and a call with one is reported as before."""
import os
import subprocess
import sys
from pathlib import Path

STUB = Path(__file__).resolve().parents[1] / "lib" / "stub_curl"
failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


def call(*args, env=None):
    return subprocess.run(["bash", str(STUB), *args], capture_output=True, text=True, env=dict(os.environ, **(env or {})))


r = call("-s", "-k", "-X", "GET", "https://st.example.com:8444/api/v2.0/myself", "-H", "accept: application/json")
check("a call with no Referer header exits 22 and says which call", r.returncode == 22 and "has no Referer header" in r.stderr
      and "https://st.example.com:8444/api/v2.0/myself" in r.stderr, (r.returncode, r.stderr))
r = call("-s", "-k", "-X", "GET", "https://st.example.com:8444/api/v2.0/myself", "-H", "accept: application/json", "-H", "Referer: THIS_IS_A_RANDOM_TEXT")
check("a call with one is reported (URL and method)", r.returncode == 0 and "URL: https://st.example.com:8444/api/v2.0/myself" in r.stderr, (r.returncode, r.stderr))
r = call("-s", "-k", "https://st.example.com:8444/api/v2.0/myself", "-H", "referer: lower case")
check("the name of the header is not case sensitive", r.returncode == 0, r.stderr)
r = call("-s", "-k", "https://st.example.com:8444/api/v2.0/myself", env={"STUB_CURL_REQUIRE_REFERER": "0"})
check("STUB_CURL_REQUIRE_REFERER=0 turns it off, for a test about a call with none", r.returncode == 0, r.stderr)
print("test_stubs: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
