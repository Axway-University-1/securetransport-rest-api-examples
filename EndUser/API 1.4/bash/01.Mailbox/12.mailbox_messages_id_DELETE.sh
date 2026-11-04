#!/bin/bash
# ==============================================================================
# Script Name: 12.mailbox_messages_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a message, or a draft, with `DELETE /api/v1.4/mailbox/messages/{messageId}`.
#
# Usage:
# ./12.mailbox_messages_id_DELETE.sh MESSAGE_ID
#
#   MESSAGE_ID  the id of the message
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly: the answer is 200 {"info": "Deletion was successful"}. It deletes the message of THIS user only: the copy in the Sent folder of the sender stays until he deletes it.
# - The mailbox of a user outlives his account (see 02), and the messages of a deleted account cannot be deleted any more (404). A test that sends messages should delete them with this call BEFORE it deletes the account.
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

USAGE="Usage: ./12.mailbox_messages_id_DELETE.sh MESSAGE_ID"
if [ "$#" -lt 1 ] || [ "$#" -gt 1 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
MESSAGE_ID="$1"
if [[ ! "${MESSAGE_ID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "MESSAGE_ID is '%s': the id of a message as the folder lists it (letters and digits, 32 characters).\n%s\n" "${MESSAGE_ID}" "${USAGE}"
    exit 2
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/messages/${MESSAGE_ID}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not delete the message (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf "HTTP 200: %s\n" "$(printf '%s' "${BODY}" | jq -r '.info // .')"
