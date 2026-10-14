#!/bin/bash
# ==============================================================================
# Script Name: 06.session_expired_recovery.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# What a script does when its session is gone. It tries a call with a cookie
# the server does not know (as after an expiry or a logout): the answer is 401
# or 403. It then logs in again, which gets a new session, and repeats the call.
# This is the idea behind EndUser/API 2.0/bash/ensure_session.sh.
#
# Usage:
# ./06.session_expired_recovery.sh
#
# Risk: write
#
# Notes:
# - The expired session is imitated with a made-up cookie in a throwaway jar, so
#   the real session of 03 is neither ended nor changed.
# - Only 401 and 403 mean a lost session. Any other answer (a 500, no answer at
#   all) is a different problem and a new login would not fix it.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

stale=$(mktemp)
trap 'rm -f "${stale}"' EXIT
host="${ST_SERVER}"
printf '%s\tFALSE\t/\tTRUE\t0\tJSESSIONID\texample_expired_session\n' "#HttpOnly_${host}" > "${stale}"

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${stale}" -X GET "${ST_URL}/myself" \
       -H "accept: application/json" -H "Referer: ${REFERER}")
echo "With the expired session: HTTP ${code}"
case "${code}" in
    401|403) echo "The session is lost. Logging in again..." ;;
    *) echo "Not a lost session (expected 401 or 403)."; exit 1 ;;
esac

bash "${UC_DIR}/03.session_login_POST.sh" || exit 1
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself" \
       -H "accept: application/json" -H "Referer: ${REFERER}")
echo "With the new session: HTTP ${code}"
[[ "${code}" == 200 ]] || exit 1
