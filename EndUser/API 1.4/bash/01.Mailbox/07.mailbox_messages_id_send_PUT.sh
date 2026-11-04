#!/bin/bash
# ==============================================================================
# Script Name: 07.mailbox_messages_id_send_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script sends a draft with `PUT /api/v1.4/mailbox/messages/{messageId}/send`. The message moves from Drafts to Sent, and to the Inbox of the recipient.
#
# Usage:
# ./07.mailbox_messages_id_send_PUT.sh MESSAGE_ID [NOTIFY]
#
#   MESSAGE_ID  the id of the draft (05)
#   NOTIFY      yes to let the server send the delivery notification mail, no to switch it off (default: no)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly: the answer is 200 {"info": "Your message has been sent.", "messageId": ...}. The message reaches the Inbox of the recipient within a second or two, with the SAME id (and it is a message of the sender: it stays in his Sent folder).
# - NOTIFY no sends `disableDeliveryNotification=true`, so that a test does not mail anybody. The server's own setting can still decide.
# - Confirmed directly: a draft with no security level is refused (400 "Message security level may not be empty."), and one with no recipient (400 "Message recipient may not be empty."). A second send of the same id also answers 200, and the recipient has the message once.
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

USAGE="Usage: ./07.mailbox_messages_id_send_PUT.sh MESSAGE_ID [NOTIFY]"
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
MESSAGE_ID="$1"
NOTIFY="${2:-no}"
if [[ ! "${MESSAGE_ID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "MESSAGE_ID is '%s': the id of a message as the folder lists it (letters and digits, 32 characters).\n%s\n" "${MESSAGE_ID}" "${USAGE}"
    exit 2
fi
if [[ ! "${NOTIFY}" =~ ^(yes|no)$ ]]; then
    printf "NOTIFY is '%s': yes or no.\n%s\n" "${NOTIFY}" "${USAGE}"
    exit 2
fi
QUERY=()
[ "${NOTIFY}" = "no" ] && QUERY=(--data-urlencode "disableDeliveryNotification=true")

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT -G "${MAIN_URL}/messages/${MESSAGE_ID}/send" "${QUERY[@]}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not send the message (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf "HTTP 200: %s\n" "$(printf '%s' "${BODY}" | jq -r '.info // .')"
