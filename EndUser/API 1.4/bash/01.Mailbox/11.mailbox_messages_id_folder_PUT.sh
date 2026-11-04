#!/bin/bash
# ==============================================================================
# Script Name: 11.mailbox_messages_id_folder_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script moves a message to a folder of the mailbox with `PUT /api/v1.4/mailbox/messages/{messageId}/folder`. The call takes form data.
#
# Usage:
# ./11.mailbox_messages_id_folder_PUT.sh MESSAGE_ID FOLDER
#
#   MESSAGE_ID  the id of the message
#   FOLDER      the folder to move it to (it must exist: 03 makes one)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly: the answer is 204, and the message is in the new folder and no longer in the old one. To a folder that does not exist it answers 500 "Unable to move message. General failure." ("Internal error").
# - The reference text of this call is the one of the custom properties: it is wrong, the call moves the message.
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

USAGE="Usage: ./11.mailbox_messages_id_folder_PUT.sh MESSAGE_ID FOLDER"
if [ "$#" -lt 2 ] || [ "$#" -gt 2 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
MESSAGE_ID="$1"
FOLDER="$2"
if [[ ! "${MESSAGE_ID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "MESSAGE_ID is '%s': the id of a message as the folder lists it (letters and digits, 32 characters).\n%s\n" "${MESSAGE_ID}" "${USAGE}"
    exit 2
fi
if [ -z "${FOLDER}" ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/messages/${MESSAGE_ID}/folder" --data-urlencode "name=${FOLDER}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf "Could not move the message (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf "The message is in %s now (HTTP 204).\n" "${FOLDER}"
