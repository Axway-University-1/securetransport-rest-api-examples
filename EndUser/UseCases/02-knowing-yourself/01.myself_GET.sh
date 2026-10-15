#!/bin/bash
# ==============================================================================
# Script Name: 01.myself_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Who am I? GET /myself returns everything the server knows about the account: name, type, uid and gid, contact, language, the password policy and more.
#
# Usage:
# ./01.myself_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/01.myself_GET.sh.
# - The first call of a script that needs a session is st_session: it logs in only when there is none.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
echo "${result%???}" | jq .
[[ "${code}" == 200 ]] || exit 1
