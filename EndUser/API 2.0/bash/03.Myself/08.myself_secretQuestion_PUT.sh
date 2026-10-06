#!/bin/bash
# ==============================================================================
# Script Name: 08.myself_secretQuestion_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script sets the logged-in user's secret question and its answer, using
# the `/myself/secretQuestion` endpoint. A password reset may then ask for the
# answer (see 05.myself_password_POST_reset.sh).
#
# Usage:
# ./08.myself_secretQuestion_PUT.sh "QUESTION" "ANSWER"
#
#   QUESTION  one of the questions 06.secretQuestions_GET.sh lists
#   ANSWER    its answer
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - The body also carries the user's password, ST_PASSWORD, as the API requires.
# - When the secret question service is not configured or enabled, the answer
#   is 503 (confirmed directly). This script says so and exits 3.
# - A success answers 204, with no body.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

QUESTION="$1"
ANSWER="$2"
if [ -z "${QUESTION}" ] || [ -z "${ANSWER}" ]; then
    printf "Usage: ./08.myself_secretQuestion_PUT.sh \"QUESTION\" \"ANSWER\"\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

BODY=$(jq -n --arg password "${ST_PASSWORD}" --arg question "${QUESTION}" --arg answer "${ANSWER}" \
  '{password: $password, secretQuestion: $question, secretAnswer: $answer}')

printf "Setting the secret question of %s...\n" "${ST_USER}"
RESPONSE=$(curl -s -k -b "${COOKIE}" -X PUT "${ST_URL}/myself/secretQuestion" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

case "${HTTP_CODE}" in
    204)
        printf "The secret question is set.\n"
        ;;
    503)
        printf "The secret question service is not enabled on this server:\n%s\n" "${BODY}"
        exit 3
        ;;
    *)
        printf "Could not set the secret question (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
        exit 1
        ;;
esac
