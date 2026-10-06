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
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - This is the end user's view of the account. It carries fields the admin
#   API does not take, such as sharingAllowed.
# - Requires `jq`, which prints the summary.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

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
