#!/bin/bash
# ==============================================================================
# Script Name: 03.secretQuestions_GET_pick.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# This script prints the Nth question of the list the server offers, using the
# `/secretQuestions` endpoint, so that a script can use it without typing a question out:
#
#   ./03.Myself/07.myself_secretQuestion_PUT.sh "$(./07.SecretQuestions/03.secretQuestions_GET_pick.sh 8)" "Rex"
#
# Usage:
# ./03.secretQuestions_GET_pick.sh [N]
#
#   N  the number of the question, counted from 1 in the order of 01.secretQuestions_GET.sh
#      (default 1)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on. That message goes to
#   standard error, so that standard output is the question and nothing else.
# - The order is the server's, from the option Users.SecretQuestions: an administrator
#   can change it, so a number is only as steady as that list.
# - Exit codes: 0 when printed, 1 when N is past the end of the list (or the call failed),
#   2 when N is not a whole number above 0 (nothing sent), 3 when the service is not enabled.
# - Requires `jq`, which picks the question.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ENDUSER_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }
export ST_URL="${ST_URL:-https://${ST_SERVER}:${ST_PORT}/api/v2.0}"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
source "${SCRIPT_DIR}/../ensure_session.sh"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

N="${1:-1}"
if ! [[ "${N}" =~ ^[1-9][0-9]*$ ]]; then
    printf "Usage: ./03.secretQuestions_GET_pick.sh [N]  (N is a whole number above 0: %s)\n" "${N}" >&2
    exit 2
fi
st_ensure_session >&2

RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/secretQuestions" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

case "${HTTP_CODE}" in
    200)
        QUESTION=$(printf '%s' "${BODY}" | jq -r --argjson n "${N}" '.[$n - 1] // empty')
        if [ -z "${QUESTION}" ]; then
            printf "There is no question number %s: the list has %s.\n" "${N}" "$(printf '%s' "${BODY}" | jq 'length')" >&2
            exit 1
        fi
        printf '%s\n' "${QUESTION}"
        ;;
    503)
        printf "The secret question service is not enabled on this server:\n%s\n" "${BODY}" >&2
        exit 3
        ;;
    *)
        printf "Could not list the secret questions (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}" >&2
        exit 1
        ;;
esac
