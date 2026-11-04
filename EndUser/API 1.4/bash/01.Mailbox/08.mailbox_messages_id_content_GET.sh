#!/bin/bash
# ==============================================================================
# Script Name: 08.mailbox_messages_id_content_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the text of a message with `GET /api/v1.4/mailbox/messages/{messageId}/content/{streamId}`. The stream id is the one 06 shows under `text streams`.
#
# Usage:
# ./08.mailbox_messages_id_content_GET.sh MESSAGE_ID STREAM_ID
#
#   MESSAGE_ID  the id of the message
#   STREAM_ID   the stream of its text (06)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - NOT CONFIRMED to give a text: on the lab the call answers 200 with an empty list, whatever the Accept header (text/plain, text/html or any): the text of the message was never stored (see 05). With `Accept: application/json` it answers 406.
# - The reference says the call answers text/plain or text/html. The script asks for text/plain, and prints what it gets.
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

USAGE="Usage: ./08.mailbox_messages_id_content_GET.sh MESSAGE_ID STREAM_ID"
if [ "$#" -lt 2 ] || [ "$#" -gt 2 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
MESSAGE_ID="$1"
STREAM_ID="$2"
if [[ ! "${MESSAGE_ID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "MESSAGE_ID is '%s': the id of a message as the folder lists it (letters and digits, 32 characters).\n%s\n" "${MESSAGE_ID}" "${USAGE}"
    exit 2
fi
if [[ ! "${STREAM_ID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "STREAM_ID is '%s': the id of a stream as 06 shows it.\n%s\n" "${STREAM_ID}" "${USAGE}"
    exit 2
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/messages/${MESSAGE_ID}/content/${STREAM_ID}" -H "accept: text/plain" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the text (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
TRIMMED=$(printf '%s' "${BODY}" | tr -d '[:space:]')
if [ -z "${TRIMMED}" ] || [ "${TRIMMED}" = "[]" ]; then
    echo "HTTP 200, and the text is empty."
    exit 0
fi
printf '%s\n' "${BODY}"
