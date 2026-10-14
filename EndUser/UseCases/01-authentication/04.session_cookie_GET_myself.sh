#!/bin/bash
# ==============================================================================
# Script Name: 04.session_cookie_GET_myself.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# The same call as 01, now with the session: the cookie jar only (curl -b), no
# user name and no password.
#
# Usage:
# ./04.session_cookie_GET_myself.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/01.myself_GET.sh.
# - Run 03 first. Needs the session.cookie.jar it leaves.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_need_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself" \
         -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
echo "${result%???}" | jq -r '"You are " + .name + " (" + .type + ")"' 2>/dev/null || echo "${result%???}"
[[ "${code}" == 200 ]] || exit 1
