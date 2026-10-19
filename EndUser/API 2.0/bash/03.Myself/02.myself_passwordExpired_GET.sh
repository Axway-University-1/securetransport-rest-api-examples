#!/bin/bash
# ==============================================================================
# Script Name: 02.myself_passwordExpired_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether the logged-in user's password has expired, using
# the `/myself/passwordExpired` endpoint. The answer also carries the URL to
# change the password with, which 03.myself_password_POST_change.sh calls.
#
# Usage:
# ./02.myself_passwordExpired_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - The message is the server's own text, and is there even when the password
#   has not expired: read "expired".
# - Exits 2 when the password has expired, so a script can act on it.
# - Requires `jq`.
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

RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/myself/passwordExpired" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the password expiry (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
    exit 1
fi

printf '%s\n' "${BODY}"
if [ "$(printf '%s' "${BODY}" | jq -r '.expired')" = "true" ]; then
    printf "\nThe password has expired. Change it at %s\n" "$(printf '%s' "${BODY}" | jq -r '.changePasswordURL')"
    exit 2
fi
printf "\nThe password has not expired.\n"
