#!/bin/bash
# ==============================================================================
# Script Name: 03.myself_passwordExpired_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Has the password expired? GET /myself/passwordExpired answers with expired true or false. A script can check it before it starts, and warn instead of failing halfway.
#
# Usage:
# ./03.myself_passwordExpired_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/02.myself_passwordExpired_GET.sh.
# - The message in the answer is fixed text and is there whether or not the password has expired: read the expired field.
# - Exit 0 when the password is valid, 3 when it has expired (so a caller can tell it from a failure, exit 1).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself/passwordExpired" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || exit 1
expired=$(echo "${result%???}" | jq -r '.expired')
if [ "${expired}" = "true" ]; then
    echo "The password has expired. Change it: $(echo "${result%???}" | jq -r '.changePasswordURL')"
    exit 3
fi
echo "The password has not expired."
