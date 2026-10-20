#!/bin/bash
# ==============================================================================
# Script Name: 02.secretQuestion_GET_mine.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Do I have a secret question? GET /myself/secretQuestion answers with the question, never the answer. The server answers 503 "service not available" for an account that has none, the same as when the service is off, so this asks the list as well, to tell the two apart.
#
# Usage:
# ./02.secretQuestion_GET_mine.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/06.myself_secretQuestion_GET.sh.
# - Exit 0 when the account has a question, 4 when the service is on and the account has none, 3 when the service is not enabled.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself/secretQuestion" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
case "${code}" in
    200) echo "The secret question of ${ST_USER}: $(echo "${result%???}" | jq -r '.secretQuestion // "(none)"')" ;;
    503)
        st_list_questions || exit $?
        echo "The service is on, and ${ST_USER} has no secret question yet (the server answers 503 for that too)."
        exit 4
        ;;
    *) echo "Could not read the secret question (HTTP ${code}): ${result%???}"; exit 1 ;;
esac
