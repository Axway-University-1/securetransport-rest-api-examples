#!/bin/bash
# ==============================================================================
# Script Name: 01.mailbox_myself_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the mailbox user of the logged-in end user with `GET /api/v1.4/mailbox/myself`: his name, his email address (the address a message to him is sent to) and whether he is a licensed or an
# unlicensed user. The mailbox of the API 1.4 is not in the API 2.0.
#
# Usage:
# ./01.mailbox_myself_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly on 5.5-20260924: the answer is {username, email, displayName, unlicensed, ...}. The email is the `contact.email` of the account. An account without one cannot receive a message.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ENDUSER_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v1.4/mailbox"

# The reason of a refusal: the mailbox answers {"error", "errorDescription"}, other answers {"message"}
reason() { printf '%s' "$1" | jq -r '[.error, .errorDescription, .message] | map(select(. != null and . != "")) | join(" - ")' 2>/dev/null; }

USAGE="Usage: ./01.mailbox_myself_GET.sh"
if [ "$#" -lt 0 ] || [ "$#" -gt 0 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/myself" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the mailbox user (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf '%s' "${BODY}" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
