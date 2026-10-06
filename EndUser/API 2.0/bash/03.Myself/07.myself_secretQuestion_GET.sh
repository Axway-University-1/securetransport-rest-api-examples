#!/bin/bash
# ==============================================================================
# Script Name: 07.myself_secretQuestion_GET.sh
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
# ./07.myself_secretQuestion_GET.sh [TOKEN]
#
#   TOKEN  the security token from a password reset email. Without it, the
#          logged-in user's own question is read.
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Without a token, a session must already exist. Run
#   01.Authenticate/01.myself_POST.sh first.
# - When the secret question service is not configured or enabled, the answer
#   is 503 (confirmed directly). This script says so and exits 3.
# - Requires `jq`.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

TOKEN="$1"
if [ -n "${TOKEN}" ]; then
    # The token authenticates the request: no session, and it is URL-encoded
    RESPONSE=$(curl -s -k -G -X GET "${ST_URL}/myself/secretQuestion" --data-urlencode "token=${TOKEN}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
else
    if [ ! -f "${COOKIE}" ]; then
        printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
        exit 1
    fi
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
        printf "The secret question service is not enabled on this server:\n%s\n" "${BODY}"
        exit 3
        ;;
    *)
        printf "Could not read the secret question (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
        exit 1
        ;;
esac
