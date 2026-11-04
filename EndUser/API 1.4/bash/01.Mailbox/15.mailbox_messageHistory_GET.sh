#!/bin/bash
# ==============================================================================
# Script Name: 15.mailbox_messageHistory_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the history of a message you sent: who downloaded it, and who opened it first, with `GET /api/v1.4/mailbox/messageHistory/{messageId}/download` and `.../firstAccess`.
#
# Usage:
# ./15.mailbox_messageHistory_GET.sh MESSAGE_ID
#
#   MESSAGE_ID  the id of a message you sent (04 lists the Sent folder)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly: both calls answer 200 with an object that holds a list, `recipientsDownloadHistory` and `recipientsAccessHistory`. For a message nobody opened, both lists are empty. Once the recipient had read the message (06, 10), `firstAccess` held one entry, {"accessHistory": {userName, email, protocol, firstAccessTimestamp, ...}}, and `download` was still empty: the lab stores no content, so nothing was downloaded.
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

USAGE="Usage: ./15.mailbox_messageHistory_GET.sh MESSAGE_ID"
if [ "$#" -lt 1 ] || [ "$#" -gt 1 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
MESSAGE_ID="$1"
if [[ ! "${MESSAGE_ID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "MESSAGE_ID is '%s': the id of a message as the folder lists it (letters and digits, 32 characters).\n%s\n" "${MESSAGE_ID}" "${USAGE}"
    exit 2
fi

for WHAT in download firstAccess; do
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/messageHistory/${MESSAGE_ID}/${WHAT}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    BODY="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not read the %s history (HTTP %s): %s\n" "${WHAT}" "${HTTP_CODE}" "$(reason "${BODY}")"
        exit 1
    fi
    printf "%s: %s entries\n" "${WHAT}" "$(printf '%s' "${BODY}" | jq -r '[.[] | length] | add // 0' 2>/dev/null)"
    printf '%s' "${BODY}" | jq -r '.[] | .[]? | "  " + tojson' 2>/dev/null
done
