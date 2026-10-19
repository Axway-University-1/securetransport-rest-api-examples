#!/bin/bash
# ==============================================================================
# Script Name: 01.secretQuestions_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the secret questions a user can choose from, using the
# `/secretQuestions` endpoint. 03.Myself/07.myself_secretQuestion_PUT.sh sets one of them.
# 02 checks that a question is on the list, and 03 prints the Nth one.
#
# Usage:
# ./01.secretQuestions_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - When the secret question service is not configured or enabled, the answer
#   is 503, error.secretQuestion.serviceDisabled (confirmed directly). This
#   script says so and exits 3. The service is switched by the server option
#   Users.SecretQuestion.Enabled (false by default), and the questions on offer
#   are the option Users.SecretQuestions, which an administrator can change.
# - The answer is a plain JSON list of texts, not an object. /secretQuestions
#   takes GET only: every other method is 405.
# - Requires `jq`, which prints one question per line.
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

st_ensure_session

RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/secretQuestions" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

case "${HTTP_CODE}" in
    200)
        printf "The secret questions to choose from:\n"
        printf '%s' "${BODY}" | jq -r '.[] | "  " + .'
        ;;
    503)
        printf "The secret question service is not enabled on this server:\n%s\n" "${BODY}"
        exit 3
        ;;
    *)
        printf "Could not list the secret questions (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
        exit 1
        ;;
esac
