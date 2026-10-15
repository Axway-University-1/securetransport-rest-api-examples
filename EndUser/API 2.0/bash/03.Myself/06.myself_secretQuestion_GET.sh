#!/bin/bash
# ==============================================================================
# Script Name: 06.myself_secretQuestion_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads an account's secret question, using the
# `/myself/secretQuestion` endpoint, in one of two ways:
# - as the logged-in user, with the session from the cookie jar
# - during a password reset, with the security token from the reset email
#   instead of a session (see 04 and 05 in this folder)
#
# Usage:
# ./06.myself_secretQuestion_GET.sh [TOKEN]
#
#   TOKEN  the security token from a password reset email. Without it, the
#          logged-in user's own question is read.
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Without a token it needs a session: it checks for an active one first and, if there
#   is none, logs in with 01.Authenticate/01.myself_POST.sh.
# - Confirmed directly: the answer is 503, error.secretQuestion.serviceDisabled, "Service
#   not available.", both when the service is not enabled AND when the service is on but the
#   account has no question set yet. With a session, this script tells them apart by asking
#   07.SecretQuestions/01.secretQuestions_GET.sh's endpoint (/secretQuestions): 200 means the
#   service is on, so the account simply has none, and the script exits 4. With a token it
#   has no session to ask with, and says it is one or the other.
# - Exit codes: 0 when a question is read (or none is shown as set), 1 on an error,
#   3 when the service is not enabled, 4 when it is enabled and the account has no question.
# - Requires `jq`.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
source "${SCRIPT_DIR}/../ensure_session.sh"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

TOKEN="$1"
if [ -n "${TOKEN}" ]; then
    # The token authenticates the request: no session, and it is URL-encoded
    RESPONSE=$(curl -s -k -G -X GET "${ST_URL}/myself/secretQuestion" --data-urlencode "token=${TOKEN}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
else
    st_ensure_session
    RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/myself/secretQuestion" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
fi
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

case "${HTTP_CODE}" in
    200)
        printf "The secret question: %s\n" "$(printf '%s' "${BODY}" | jq -r '.secretQuestion // "(none set)"')"
        ;;
    503)
        if [ -n "${TOKEN}" ]; then
            printf "Service not available: the secret question service is not enabled, or the account has no question set:\n%s\n" "${BODY}"
            exit 3
        fi
        # The same 503 comes for a service that is off and for an account with no question: ask the list
        LIST_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" -b "${COOKIE}" -X GET "${ST_URL}/secretQuestions" \
          -H "accept: application/json" -H "${REFERER_HEADER}")
        if [ "${LIST_CODE}" = "200" ]; then
            printf "The service is enabled, and %s has no secret question yet (the server answers 503 for that too).\n" "${ST_USER}"
            printf "Set one with 07.myself_secretQuestion_PUT.sh.\n"
            exit 4
        fi
        printf "The secret question service is not enabled on this server:\n%s\n" "${BODY}"
        exit 3
        ;;
    *)
        printf "Could not read the secret question (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
        exit 1
        ;;
esac
