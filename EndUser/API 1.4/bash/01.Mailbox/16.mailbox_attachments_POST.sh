#!/bin/bash
# ==============================================================================
# Script Name: 16.mailbox_attachments_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script adds a file to a draft with `POST /api/v1.4/mailbox/messages/{messageId}/attachments`. The call takes a multipart upload with the field `file`.
#
# Usage:
# ./16.mailbox_attachments_POST.sh MESSAGE_ID FILE
#
#   MESSAGE_ID  the id of the draft (05)
#   FILE        the file to attach
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - NOT CONFIRMED to store the file: on the lab the call answers 422 "Failed to process item upload" (errorCode internalError), and yet the attachment is listed on the draft (06) with its name and a size of 0. The content is not stored (see 05).
# - The reference marks the other upload, `POST .../attachments/{streamId}`, as the resume of an upload that stopped. It is not used here.
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

USAGE="Usage: ./16.mailbox_attachments_POST.sh MESSAGE_ID FILE"
if [ "$#" -lt 2 ] || [ "$#" -gt 2 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
MESSAGE_ID="$1"
ATTACHMENT="$2"
if [[ ! "${MESSAGE_ID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "MESSAGE_ID is '%s': the id of a message as the folder lists it (letters and digits, 32 characters).\n%s\n" "${MESSAGE_ID}" "${USAGE}"
    exit 2
fi
if [ ! -f "${ATTACHMENT}" ] || [ ! -r "${ATTACHMENT}" ]; then
    printf "FILE is '%s': a file that can be read.\n%s\n" "${ATTACHMENT}" "${USAGE}"
    exit 2
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/messages/${MESSAGE_ID}/attachments" -F "file=@${ATTACHMENT}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ] && [ "${HTTP_CODE}" != "201" ]; then
    printf "Could not attach the file (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf "The file was attached (HTTP %s).\n" "${HTTP_CODE}"
