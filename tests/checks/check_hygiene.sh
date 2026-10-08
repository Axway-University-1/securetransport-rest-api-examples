#!/bin/bash
# ==============================================================================
# Repository hygiene.
#
# Catches the things that are easy to commit by accident and hard to take back:
# a credential, a real hostname, a customer name. Then the consistency rules
# that keep the examples usable: naming, syntax, bash and bat parity.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/../.." || exit 1

# This script must not scan itself: it necessarily contains the very patterns it
# searches for. Everything else in the repository, tests included, is scanned.
SELF="tests/checks/check_hygiene.sh"
scan_files()   { git ls-files -z | tr '\0' '\n' | grep -v "^${SELF}$" | tr '\n' '\0'; }
scan_scripts() { git ls-files -z | tr '\0' '\n' | grep -v "^${SELF}$" | grep -iE '\.(sh|bat)$' | tr '\n' '\0'; }

# The one file allowed to contain a credential shaped string. It holds obviously
# fake values so that the tests can prove variable substitution works.
CRED_EXEMPT="tests/fixtures/set_variables.test.sh"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }

echo "=== Secrets and identifying data ==="

# Base64 of common credentials, and the literals themselves
if scan_files | xargs -0 grep -lE "YWRtaW46|QVBJYWRtaW4|YXh3YXlhZG1pbg|am9objox" 2>/dev/null | grep -q .; then
    fail "base64 encoded credentials found"
    scan_files | xargs -0 grep -lE "YWRtaW46|QVBJYWRtaW4|YXh3YXlhZG1pbg|am9objox" | sed 's/^/        /'
else
    pass "no base64 encoded credentials"
fi

# Plaintext credential assignments outside the example config files
HITS=$(scan_scripts | xargs -0 grep -nE '(ADMIN_PWD|ADMIN_USER|ST_PASSWORD|ST_USER)=("?[A-Za-z0-9])' 2>/dev/null \
       | grep -v "local.example" | grep -v "^${CRED_EXEMPT}:" | grep -v '%ST_\|${ST_')
# Also check Python files for password literals
HITS_PY=$(git ls-files -z | tr '\0' '\n' | grep -iE '\.py$' | xargs -0 grep -nE '"password"\s*:\s*"[^"]*"' 2>/dev/null \
       | grep -v "change_me" | grep -v "local.example")
if [ -n "${HITS}" ] || [ -n "${HITS_PY}" ]; then
    fail "plaintext credentials in a script"
    [ -n "${HITS}" ] && echo "${HITS}" | sed 's/^/        /'
    [ -n "${HITS_PY}" ] && echo "${HITS_PY}" | sed 's/^/        /'
else
    pass "no plaintext credentials in scripts"
fi

# Internal domains, plus any identifying terms listed one per line in
# tests/local/blocked_terms.txt. That file is git ignored on purpose: a list of
# names to keep out of the repository must not itself be in the repository.
BLOCKED="axway\.university|axway\.int|axway\.cloud"
if [ -f tests/local/blocked_terms.txt ]; then
    LOCAL_TERMS=$(grep -vE '^[[:space:]]*(#|$)' tests/local/blocked_terms.txt | paste -sd'|' -)
    [ -n "${LOCAL_TERMS}" ] && BLOCKED="${BLOCKED}|${LOCAL_TERMS}"
fi
if scan_files | xargs -0 grep -lniE "${BLOCKED}" 2>/dev/null | grep -q .; then
    fail "an identifying or internal term was found"
    scan_files | xargs -0 grep -lniE "${BLOCKED}" | sed 's/^/        /'
else
    pass "no identifying or internal terms"
fi

# Routable IP literals. 127.0.0.1 and the placeholders are fine.
HITS=$(scan_files | xargs -0 grep -onE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" 2>/dev/null \
       | grep -vE ":(127\.0\.0\.1|0\.0\.0\.0|255\.255\.255\.255)$" | grep -vE "^tests/")
if [ -n "${HITS}" ]; then
    fail "IP address literal found"
    echo "${HITS}" | sed 's/^/        /'
else
    pass "no IP address literals"
fi

# Private keys must never be tracked
if git ls-files | grep -qiE "\.(pem|key|p12|pfx|jks)$|id_rsa|sshkey"; then
    fail "a key or certificate file is tracked"
    git ls-files | grep -iE "\.(pem|key|p12|pfx|jks)$|id_rsa|sshkey" | sed 's/^/        /'
else
    pass "no key or certificate files tracked"
fi

# The real config files must stay out
for f in "Admin/API 2.0/python/config" "Admin/API 2.0/bash/set_variables.local.sh" \
         "Admin/API 2.0/bat/set_variables.local.bat" "EndUser/API 2.0/bash/set_variables.local.sh" \
         ".claude/settings.local.json"; do
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        fail "tracked but should be ignored: $f"
    fi
done
pass "no local configuration files tracked"

# Nothing under tests/local or tests/output should ever be tracked
if git ls-files | grep -qE "^tests/(local|output)/"; then
    fail "something under tests/local or tests/output is tracked"
    git ls-files | grep -E "^tests/(local|output)/" | sed 's/^/        /'
else
    pass "tests/local and tests/output are not tracked"
fi

echo
echo "=== Naming ==="

if git ls-files | grep -qE '\.[A-Za-z0-9]*[A-Z][A-Za-z0-9]*$'; then
    fail "a file has a non lower case extension"
    git ls-files | grep -E '\.[A-Za-z0-9]*[A-Z][A-Za-z0-9]*$' | sed 's/^/        /'
else
    pass "all extensions are lower case"
fi

# A space in the last path segment, which is the filename. Note that every path
# in this repository contains "API 2.0", so only the basename may be tested.
SPACED=$(git ls-files | grep -E '(^|/)[^/]* [^/]*$')
if [ -n "${SPACED}" ]; then
    fail "a filename contains a space"
    echo "${SPACED}" | sed 's/^/        /'
else
    pass "no spaces in filenames"
fi

if git ls-files | grep -qE '/[0-9]+_'; then
    fail "a file uses an underscore straight after its number"
else
    pass "numbering uses a dot, not an underscore"
fi

echo
echo "=== Syntax ==="

SYNTAX=0
while IFS= read -r f; do
    bash -n "$f" 2>/dev/null || { fail "does not parse: $f"; SYNTAX=1; }
done < <(git ls-files -z | tr '\0' '\n' | grep -iE '\.sh$')
[ "${SYNTAX}" -eq 0 ] && pass "every shell file parses ($(git ls-files | grep -icE '\.sh$') checked)"

PY=0
while IFS= read -r f; do
    python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" 2>/dev/null \
        || { fail "does not parse: $f"; PY=1; }
done < <(git ls-files -z | tr '\0' '\n' | grep -iE '\.py$')
[ "${PY}" -eq 0 ] && pass "every python file parses ($(git ls-files | grep -icE '\.py$' ) checked)"

JSON=0
while IFS= read -r f; do
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null \
        || { fail "not valid JSON: $f"; JSON=1; }
done < <(git ls-files -z | tr '\0' '\n' | grep -iE '\.json$')
[ "${JSON}" -eq 0 ] && pass "every JSON file parses"

echo
echo "=== Conventions ==="

# bash and bat parity
#
# 14.ExpressionLanguage is deliberately excluded: it was scoped to bash and
# python3 only when added (see its own folder and
# python/python3/14.ExpressionLanguage), not bat, and is excluded here rather
# than failing this check on every run.
B=$(cd "Admin/API 2.0/bash" && find . -name '*.sh' ! -name 'set_variables*' \
    ! -path './14.ExpressionLanguage/*' | sed 's/\.sh$//' | sort)
T=$(cd "Admin/API 2.0/bat"  && find . -name '*.bat' ! -name 'set_variables*' | sed 's/\.bat$//' | sort)
if [ "${B}" = "${T}" ]; then
    pass "bash and bat at parity ($(echo "${B}" | wc -l | tr -d ' ') examples each)"
else
    fail "bash and bat differ"
    diff <(echo "${B}") <(echo "${T}") | sed 's/^/        /'
fi

# Feature examples: every .sh has a .bat twin beside it, and the other way round
FB=$(cd Features && git ls-files '*.sh'  | sed 's/\.sh$//'  | sort)
FT=$(cd Features && git ls-files '*.bat' | sed 's/\.bat$//' | sort)
if [ "${FB}" = "${FT}" ]; then
    pass "Features: bash and bat at parity ($(echo "${FB}" | grep -c .) examples each)"
else
    fail "Features: bash and bat differ"
    diff <(echo "${FB}") <(echo "${FT}") | sed 's/^/        /'
fi

# .gitattributes makes a Linux checkout write the bat files with CRLF, so the
# name must be read without the carriage return. The self-test proves it with a
# CRLF file, because a macOS working tree is not converted and would hide it.
script_name_of() {
    grep -m1 -E "^(#|REM) Script Name:" "$1" 2>/dev/null | tr -d '\r' | sed -E 's/^(#|REM) Script Name:[[:space:]]*//'
}
CRLF_SAMPLE=$(mktemp)
printf 'REM Script Name: sample.bat\r\nREM Author: x\r\n' > "${CRLF_SAMPLE}"
if [ "$(script_name_of "${CRLF_SAMPLE}")" = "sample.bat" ]; then
    pass "a Script Name header is read correctly from a CRLF file"
else
    fail "a Script Name header is not read correctly from a CRLF file"
fi
rm -f "${CRLF_SAMPLE}"

# Script Name header must match the filename
BADHDR=$(git ls-files -z "*.sh" "*.bat" | tr '\0' '\n' | while IFS= read -r f; do
    name=$(script_name_of "$f")
    [ -n "$name" ] && [ "$name" != "$(basename "$f")" ] && echo "$f -> $name"
done)
if [ -n "${BADHDR}" ]; then
    fail "a Script Name header does not match its filename"
    echo "${BADHDR}" | sed 's/^/        /'
else
    pass "every Script Name header matches its filename"
fi

# Credentials passed to curl -u must be quoted, or a password with a space or a
# shell character in it is split or expanded before curl ever sees it
if scan_scripts | xargs -0 grep -nE -- '-u \$' 2>/dev/null | grep -q .; then
    fail "curl -u with unquoted credentials"
    scan_scripts | xargs -0 grep -nE -- '-u \$' | sed 's/^/        /'
else
    pass "curl -u credentials are always quoted"
fi

# In a batch file, cmd reads a single % as the start of a variable, so
# -w "%{http_code}" loses everything up to the next %, the credentials with it.
# It must be written %%{http_code}, which cmd turns back into %{http_code}.
if git ls-files -z '*.bat' | xargs -0 grep -nE '(^|[^%])%\{http_code\}' 2>/dev/null | grep -q .; then
    fail "bat: curl -w with a single %, which cmd eats"
    git ls-files -z '*.bat' | xargs -0 grep -nE '(^|[^%])%\{http_code\}' | sed 's/^/        /'
else
    pass "bat: curl -w always uses %%{http_code}"
fi

# %NAME: =%%20% does not give %20: the replacement ends at the next %, so the
# space is dropped and a stray 0 is left behind. Write the encoded name instead.
if git ls-files -z '*.bat' | xargs -0 grep -nE '=%%20%' 2>/dev/null | grep -q .; then
    fail "bat: a %VAR: =%%20% substitution, which does not URL-encode"
    git ls-files -z '*.bat' | xargs -0 grep -nE '=%%20%' | sed 's/^/        /'
else
    pass "bat: no %VAR: =%%20% substitutions"
fi

# An RFC 2822 date built in PowerShell: zzz writes the offset as +03:00, which
# RFC 2822 does not allow, and ddd/MMM follow the Windows language unless the
# culture is fixed. Each zzz must be stripped of its colon, and a line that
# formats day names must use the invariant culture.
BADDATE=$(git ls-files -z '*.bat' | xargs -0 grep -nE 'zzz|ddd, dd MMM' 2>/dev/null | python3 -c '
import re, sys
for line in sys.stdin:
    zzz = line.count("zzz")
    stripped = line.count("ToString(\x27zzz\x27).Replace(\x27:\x27,\x27\x27)")
    if zzz != stripped or ("ddd," in line and "InvariantCulture" not in line):
        print(line.rstrip()[:160])
')
if [ -n "${BADDATE}" ]; then
    fail "bat: an RFC 2822 date with a +03:00 offset or local day names"
    echo "${BADDATE}" | sed 's/^/        /'
else
    pass "bat: RFC 2822 dates use +0300 offsets and English day names"
fi

# No in place sed, which is not portable between BSD and GNU
if scan_scripts | xargs -0 grep -l "sed -i" 2>/dev/null | grep -q .; then
    fail "sed -i used, which differs between macOS and Linux"
else
    pass "no in place sed"
fi

# Config must be resolved from the script, not the working directory
if scan_scripts | xargs -0 grep -l 'source "\.\./set_variables.sh"' 2>/dev/null | grep -q .; then
    fail "a script sources set_variables relative to the working directory"
else
    pass "config always resolved from the script directory"
fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "check_hygiene: PASS"
else
    echo "check_hygiene: FAIL"
fi
exit "${FAILED}"
