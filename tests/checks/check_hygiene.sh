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
if [ -n "${HITS}" ]; then
    fail "plaintext credentials in a script"
    echo "${HITS}" | sed 's/^/        /'
else
    pass "no plaintext credentials in scripts"
fi

# Customer and lab identifiers that were scrubbed once already
if scan_files | xargs -0 grep -lniE "gilead|GFTS|citiconnect|\.citi\.|dogco|axway\.university|axway\.int|axway\.cloud" 2>/dev/null | grep -q .; then
    fail "customer or internal lab identifier found"
    scan_files | xargs -0 grep -lniE "gilead|GFTS|citiconnect|\.citi\.|dogco|axway\.university|axway\.int|axway\.cloud" | sed 's/^/        /'
else
    pass "no customer or internal lab identifiers"
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

# Script Name header must match the filename
BADHDR=$(git ls-files -z "*.sh" "*.bat" | tr '\0' '\n' | while IFS= read -r f; do
    name=$(grep -m1 -E "^(#|REM) Script Name:" "$f" 2>/dev/null | sed -E 's/^(#|REM) Script Name:[[:space:]]*//')
    [ -n "$name" ] && [ "$name" != "$(basename "$f")" ] && echo "$f -> $name"
done)
if [ -n "${BADHDR}" ]; then
    fail "a Script Name header does not match its filename"
    echo "${BADHDR}" | sed 's/^/        /'
else
    pass "every Script Name header matches its filename"
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
