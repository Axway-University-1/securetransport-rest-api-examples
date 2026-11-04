#!/bin/bash
# ==============================================================================
# Script Name: 10.mailbox_messages_id_customProperties_PUT_read.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script marks a message read, or unread again, with `PUT /api/v1.4/mailbox/messages/{messageId}/customProperties` and the property `isRead`. The body is JSON.
#
# Usage:
# ./10.mailbox_messages_id_customProperties_PUT_read.sh MESSAGE_ID [READ]
#
#   MESSAGE_ID  the id of the message
#   READ        true or false (default: true)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly: the answer is 204, and then the message has `unread` false (06) and `isRead` "true" (09). The call REPLACES the properties of the message with the ones it sends: this script sends isRead only.
# - Reading a message with 06 does not mark it read: this is the call that does.
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

USAGE="Usage: ./10.mailbox_messages_id_customProperties_PUT_read.sh MESSAGE_ID [READ]"
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
MESSAGE_ID="$1"
READ="${2:-true}"
if [[ ! "${MESSAGE_ID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "MESSAGE_ID is '%s': the id of a message as the folder lists it (letters and digits, 32 characters).\n%s\n" "${MESSAGE_ID}" "${USAGE}"
    exit 2
fi
if [[ ! "${READ}" =~ ^(true|false)$ ]]; then
    printf "READ is '%s': true or false.\n%s\n" "${READ}" "${USAGE}"
    exit 2
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/messages/${MESSAGE_ID}/customProperties" -H "Content-Type: application/json" \
  -d "$(jq -cn --arg read "${READ}" '{packageCustomProperties: [{name: "isRead", value: $read}]}')" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf "Could not set isRead (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf "isRead is %s (HTTP 204).\n" "${READ}"
