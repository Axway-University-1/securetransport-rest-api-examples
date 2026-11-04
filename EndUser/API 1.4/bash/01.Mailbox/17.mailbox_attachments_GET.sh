#!/bin/bash
# ==============================================================================
# Script Name: 17.mailbox_attachments_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script downloads an attachment of a message with `GET /api/v1.4/mailbox/messages/{messageId}/attachments/{streamId}/{filename}` and saves it in a file. The stream id and the file name are the ones 06 shows under `attachments`.
#
# Usage:
# ./17.mailbox_attachments_GET.sh MESSAGE_ID STREAM_ID FILENAME [OUTPUT]
#
#   MESSAGE_ID  the id of the message
#   STREAM_ID   the stream of the attachment (06)
#   FILENAME    the name of the attachment (06)
#   OUTPUT      where to save it (default: FILENAME in the current folder); a file that exists is never overwritten
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - NOT CONFIRMED to give the content: written from the reference. The lab stores no attachment content (see 16), so there was nothing to download.
# - The script saves the answer only when it is 200, and removes the file otherwise.
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

USAGE="Usage: ./17.mailbox_attachments_GET.sh MESSAGE_ID STREAM_ID FILENAME [OUTPUT]"
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
MESSAGE_ID="$1"
STREAM_ID="$2"
FILENAME="$3"
OUTPUT="${4:-${FILENAME}}"
if [[ ! "${MESSAGE_ID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "MESSAGE_ID is '%s': the id of a message as the folder lists it (letters and digits, 32 characters).\n%s\n" "${MESSAGE_ID}" "${USAGE}"
    exit 2
fi
if [[ ! "${STREAM_ID}" =~ ^[A-Za-z0-9_-]+$ ]] || [ -z "${FILENAME}" ] || [[ "${FILENAME}" == */* ]]; then
    printf "STREAM_ID is '%s' and FILENAME is '%s': a stream id as 06 shows it, and a file name with no slash.\n%s\n" "${STREAM_ID}" "${FILENAME}" "${USAGE}"
    exit 2
fi
if [ -e "${OUTPUT}" ]; then
    printf "%s exists already: it is not overwritten. Give another OUTPUT.\n" "${OUTPUT}"
    exit 2
fi
ENCODED=$(jq -rn --arg v "${FILENAME}" '$v|@uri')

HTTP_CODE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/messages/${MESSAGE_ID}/attachments/${STREAM_ID}/${ENCODED}" -H "${REFERER_HEADER}" -o "${OUTPUT}" -w "%{http_code}")
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not download the attachment (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "$(cat "${OUTPUT}" 2>/dev/null)")"
    rm -f "${OUTPUT}"
    exit 1
fi
printf "Saved %s (%s bytes).\n" "${OUTPUT}" "$(wc -c < "${OUTPUT}" | tr -d ' ')"
