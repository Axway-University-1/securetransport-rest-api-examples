#!/bin/bash
# ==============================================================================
# Script Name: 03.session_login_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# From Basic authentication to a session. POST /myself checks the password once and returns a session cookie, kept in a cookie jar, and a csrfToken in the response headers. The next scripts send the cookie and no password.
#
# Usage:
# ./03.session_login_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/01.Authentication/01.myself_cookie_POST.sh.
# - POST /myself is a login call, not a way to read the account: its answer is just {"message": "Logged in"}.
# - The session ends with 07.logout_DELETE.sh, or when it expires.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

rm -f "${JAR}" "${CSRF_FILE}"
headers=$(mktemp)
trap 'rm -f "${headers}"' EXIT

result=$(curl -k -s -w "%{http_code}" -D "${headers}" --cookie-jar "${JAR}" \
         -u "${ST_USER}:${ST_PASSWORD}" -X POST "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}: $(echo "${result%???}" | jq -r '.message // empty' 2>/dev/null)"
if [[ "${code}" != 200 ]]; then
    echo "Login failure."
    rm -f "${JAR}"
    exit 1
fi

# The csrfToken header, kept for 05 and 07. The cookie itself is in the jar.
tr -d '\r' < "${headers}" | sed -n 's/^[Cc][Ss][Rr][Ff][Tt]oken: *//p' > "${CSRF_FILE}"
echo "Session cookie saved in $(basename "${JAR}")."
[ -s "${CSRF_FILE}" ] && echo "csrfToken received (saved in $(basename "${CSRF_FILE}"))." || echo "No csrfToken in the answer."
