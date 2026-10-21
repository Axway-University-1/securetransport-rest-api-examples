#!/bin/bash
# ==============================================================================
# Script Name: 02.secretQuestions_GET_check.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# This script checks that a question is on the list the server offers, using the
# `/secretQuestions` endpoint, before it is sent to 03.Myself/07.myself_secretQuestion_PUT.sh.
# A question that is not on the list is refused there with 400,
# error.secretQuestion.notFound, so it is cheaper to ask first.
#
# Usage:
# ./02.secretQuestions_GET_check.sh "QUESTION"
#
#   QUESTION  the question, exactly as 01.secretQuestions_GET.sh prints it
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - The match is exact, case and punctuation included: "What is your dog's name?" is on the
#   default list and "what is your dog's name" is not.
# - Exit codes: 0 when the question is on the list, 1 when it is not (or the call failed),
#   2 when no question was given (nothing sent), 3 when the service is switched off (an administrator must switch it on).
# - Requires `jq`, which does the comparison.
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

QUESTION="$1"
if [ -z "${QUESTION}" ]; then
    printf "Usage: ./02.secretQuestions_GET_check.sh \"QUESTION\"\n"
    exit 2
fi
st_ensure_session

RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/secretQuestions" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

case "${HTTP_CODE}" in
    200)
        if printf '%s' "${BODY}" | jq -e --arg q "${QUESTION}" 'index($q) != null' >/dev/null; then
            printf "On the list: %s\n" "${QUESTION}"
        else
            printf "Not on the list: %s\n" "${QUESTION}"
            printf "Run 01.secretQuestions_GET.sh to see the questions on offer.\n"
            exit 1
        fi
        ;;
    503)
        printf "The secret question service is switched off on this server (HTTP 503). An administrator must switch it on: the server option Users.SecretQuestion.Enabled has to be true.\n%s\n" "${BODY}"
        exit 3
        ;;
    *)
        printf "Could not list the secret questions (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
        exit 1
        ;;
esac
