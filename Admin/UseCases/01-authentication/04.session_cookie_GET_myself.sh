#!/bin/bash
# ==============================================================================
# Script Name: 04.session_cookie_GET_myself.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# The same call as 01, now with the session: the cookie jar only (curl -b), no user name and no password.
#
# Usage:
# ./04.session_cookie_GET_myself.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/02.Introduction/03.myself_GET.sh.
# - Run 03 first. Needs the session.cookie.jar it leaves.
# - A GET in a session needs no csrfToken: the token gates writes, not reads.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
if [ ! -f "${JAR}" ]; then
    echo "There is no session yet: run 03.session_login_POST.sh first (or 00.run_all.sh)."
    exit 2
fi

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
echo "${result%???}" | jq -r '"You are " + .loginName + ", role " + .roleName' 
