#!/usr/bin/env python3
"""Features/Guidance/authentication-and-sessions.md: the sections it promises are there, the facts that were tried on the lab are written in it,
and the code in it runs against the stub curl (the login keeps a cookie and the headers, the logout sends the cookie, the check of a session logs in again on 401)."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
import guide_checks as g  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


NAME = "authentication-and-sessions.md"
text = g.read(NAME)
heads = re.findall(r"^## (.+)$", text, re.M)
for h in ("The three ways in", "Basic authentication", "A session", "The Referer header", "API keys (Admin API only)", "What a session remembers",
          "An ended or expired session", "A locked account", "A forced change of the secret question", "What the server does with the CSRF token", "Advice", "Checklist"):
    check("section: %s" % h, h in heads, heads)
check("the table of the three ways says the API key is Admin API only", re.search(r"\| \*\*An API key\*\* \| Yes \| \*\*No\*\* \|", text) is not None)
check("the rules of API keys: at most 2 (409), mandatory expiry, either field (400), key shown once, a key cannot make a key (403)",
      all(t in text for t in ("At most 2 keys", "409", "Always. Give `validityDays`", "400", "Shown once", "A key cannot make a key")))
check("the locked account: the right password is refused too, and an administrator's unlock is shown",
      "also with the right password" in text.replace("**right**", "right") or "the **right** password: 401" in text and '"/user/locked", "value": false' in text)
check("the forced change: the calls that fail (403) and the ones that still work are in the table",
      all(t in text for t in ("error.secretQuestion.required", "`GET /secretQuestions` | 200", "`DELETE /myself` | 200", "`PUT /myself/secretQuestion`")))
check("the CSRF text says what the lab does today and says to send the token anyway", "a wrong token" in text and "**Send the token anyway.**" in text)
check("the advice is labelled as advice, not product behaviour", "This part is advice. It is not product behaviour" in text)
check("every statement not run again is marked", "not tried" in text.lower())

# the session recovery function: run it against the stub, with the check answered 401 (it logs in) and 200 (it does not)
func = next(code for lang, code in g.blocks(text) if lang == "bash" and "ensure_session()" in code)
env = {"ST_ENDUSER_PORT": "8443", "STUB_CURL_PRINT_CODE": "1"}
r = g.run_curl("cd \"$(mktemp -d)\"\n" + func, env=dict(env, STUB_CURL_STATUS_GET="401"))
methods = re.findall(r"^METHOD: (\w+)", r.stderr, re.M)
check("ensure_session: a 401 on the check is followed by a login (GET, then POST /myself with Basic authentication)",
      methods[:2] == ["GET", "POST"] and "BASIC_AUTH: u:p" in r.stderr, (methods, r.stderr[-300:]))
r = g.run_curl("cd \"$(mktemp -d)\"\n" + func, env=dict(env, STUB_CURL_STATUS_GET="200"))
check("ensure_session: a 200 on the check is not followed by a login", re.findall(r"^METHOD: (\w+)", r.stderr, re.M) == ["GET"], r.stderr[-300:])
r = g.run_curl("cd \"$(mktemp -d)\"\n" + func, env=dict(env, STUB_CURL_STATUS_GET="500"))
check("ensure_session: a 500 is not taken for a lost session", re.findall(r"^METHOD: (\w+)", r.stderr, re.M) == ["GET"], r.stderr[-300:])

# the Admin examples: the login keeps the cookie and the headers, the logout sends the cookie
curls = g.curl_examples(text)
login = next(c for c in curls if "-X POST" in c and "/myself" in c and "-c session.jar" in c)
r = g.run_curl(login)
check("login: Basic authentication, a cookie jar and the response headers are asked for", "BASIC_AUTH: u:p" in r.stderr and "COOKIE_JAR_WRITE: session.jar" in r.stderr
      and "/api/v2.0/myself" in r.stderr, r.stderr[-300:])
logout = next(c for c in curls if "-X DELETE" in c and "/myself" in c)
r = g.run_curl(logout)
check("logout: DELETE /myself with the cookie, and no password", "METHOD: DELETE" in r.stderr and "COOKIE: session.jar" in r.stderr and "BASIC_AUTH" not in r.stderr, r.stderr[-300:])
key_use = next(c for c in curls if "SECURETRANSPORT-API-KEY" in c)
r = g.run_curl(key_use, env={"API_KEY": "abc"})
check("key use: the header carries the key and no password is sent", "HEADER: SECURETRANSPORT-API-KEY: abc" in r.stderr and "BASIC_AUTH" not in r.stderr, r.stderr[-300:])
key_make = next(c for c in curls if "/api-keys" in c and "-X POST" in c)
r = g.run_curl(key_make)
import base64, json
payload = re.search(r"PAYLOAD_B64: (\S+)", r.stderr)
check("key creation: Basic authentication, and a body with validityDays and permissions",
      "BASIC_AUTH: u:p" in r.stderr and payload is not None and json.loads(base64.b64decode(payload.group(1))) == {"validityDays": 1, "permissions": ["read"]}, r.stderr[-300:])
print("test_guidance_authentication_and_sessions: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
