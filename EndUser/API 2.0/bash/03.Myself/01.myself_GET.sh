#!/bin/bash
# ==============================================================================
# Script Name: 01.myself_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the account of the logged-in user using the `/myself`
# endpoint. It demonstrates:
# - Reading the whole account, as the user sees it
# - Picking out what an end user usually needs: the email, whether sharing and
#   the transfers API are allowed, the address book settings and the password
#   policy
#
# Usage:
# ./01.myself_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - This is the end user's view of the account. It carries fields the admin
#   API does not take, such as sharingAllowed.
# - Requires `jq`, which prints the summary.
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

RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/myself" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the account (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
    exit 1
fi

printf '%s\n' "${BODY}"
printf "\nIn short:\n"
printf '%s' "${BODY}" | jq -r '
  "  account           \(.name) (\(.type))",
  "  email             \(.contact.email // "")",
  "  sharing allowed   \(.sharingAllowed)",
  "  transfers API     \(.transfersWebServiceAllowed)",
  "  address book      \(if .addressBookSettings.enabled then "enabled" else "disabled" end)",
  "  message           \(.messageOfTheDay // "")"'
