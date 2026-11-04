#!/bin/bash
# ==============================================================================
# Script Name: 06.mailbox_messages_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one message, a draft or a received one, with `GET /api/v1.4/mailbox/messages/{messageId}`: who sent it and to whom, its folder, whether it is unread, its security level, and the streams of its text and its attachments (the ids 08 and 17 take).
#
# Usage:
# ./06.mailbox_messages_id_GET.sh MESSAGE_ID
#
#   MESSAGE_ID  the id of the message (04 lists them; 05 prints the id of a draft)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly: reading a message does NOT mark it read. `unread` stays true until 10 sets `isRead`.
# - On the lab the `size` of a text is 0, and so is the size of an attachment that was uploaded: the content of a message is not stored there (see 05).
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

USAGE="Usage: ./06.mailbox_messages_id_GET.sh MESSAGE_ID"
if [ "$#" -lt 1 ] || [ "$#" -gt 1 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
MESSAGE_ID="$1"
if [[ ! "${MESSAGE_ID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "MESSAGE_ID is '%s': the id of a message as the folder lists it (letters and digits, 32 characters).\n%s\n" "${MESSAGE_ID}" "${USAGE}"
    exit 2
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/messages/${MESSAGE_ID}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the message (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf '%s' "${BODY}" | jq -r '"  subject: \(.subject)", "  folder: \(.folder)", "  from: \(.sender.address // "-")", "  to: \([.recipients[]? | select(.category == "to") | .address] | join(", "))",
  "  unread: \(.unread)", "  draft: \(.isDraft // false)", "  security: \(.security)", "  size: \(.size)",
  "  text streams: \([.content[]? | .streamId + " (" + .type + ", " + (.size|tostring) + " bytes)"] | join(", "))",
  "  attachments: \([.attachments[]? | .streamId + " " + .filename + " (" + (.size|tostring) + " bytes)"] | join(", "))"'
