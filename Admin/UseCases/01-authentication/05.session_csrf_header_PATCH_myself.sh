#!/bin/bash
# ==============================================================================
# Script Name: 05.session_csrf_header_PATCH_myself.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# A write inside a session, with the csrfToken the login returned sent back as the csrfToken header. It changes nothing: it patches the administrator's own preferredFileTrackingColumns to the value it already has, and checks that it is the same afterwards. It also asks the server whether it enforces the token.
#
# Usage:
# ./05.session_csrf_header_PATCH_myself.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/02.Introduction/04.myself_PATCH.sh, with the session and the token instead of Basic authentication.
# - With Webservices.Admin.CsrfToken.enabled true (the default since 20230525) a write in a session must carry the token. The lab accepts it without, and even with a wrong one, so a script that leaves it out works there and fails on a server that enforces it: send it.
# - Only /passwordCredentials/password and /preferredFileTrackingColumns can be patched on /myself.
# - Run 03 first.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
if [ ! -f "${JAR}" ]; then
    echo "There is no session yet: run 03.session_login_POST.sh first (or 00.run_all.sh)."
    exit 2
fi
TOKEN=$(cat "${CSRF_FILE}" 2>/dev/null)
if [ -z "${TOKEN}" ]; then
    echo "03 saved no csrfToken (the server did not send one), so there is nothing to add."
    exit 1
fi

echo "Does the server enforce the token? Webservices.Admin.CsrfToken.enabled = $(curl -k -s -G -b "${JAR}" "${ST_URL}/configurations/options" \
     --data-urlencode "name=Webservices.Admin.CsrfToken.enabled" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r '.result[0].values[0] // "unknown"')"

BEFORE=$(curl -k -s -b "${JAR}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -S .preferredFileTrackingColumns)
[ -n "${BEFORE}" ] && [ "${BEFORE}" != "null" ] || { echo "Could not read preferredFileTrackingColumns."; exit 1; }
BODY=$(echo "${BEFORE}" | jq -c '[{op: "replace", path: "/preferredFileTrackingColumns", value: .}]')

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" \
       -H "Content-Type: application/json" -H "csrfToken: ${TOKEN}" -d "${BODY}")
echo "PATCH /myself with the csrfToken header: HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1

AFTER=$(curl -k -s -b "${JAR}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -S .preferredFileTrackingColumns)
[ "${BEFORE}" = "${AFTER}" ] && echo "Unchanged, as it should be." || { echo "The value changed."; exit 1; }
