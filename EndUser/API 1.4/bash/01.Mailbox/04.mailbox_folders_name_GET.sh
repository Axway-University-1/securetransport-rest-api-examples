#!/bin/bash
# ==============================================================================
# Script Name: 04.mailbox_folders_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the messages of one mailbox folder with `GET /api/v1.4/mailbox/folders/{name}`: the id of each message (the other examples take it), who sent it, whether it is unread, and the subject.
#
# Usage:
# ./04.mailbox_folders_name_GET.sh [FOLDER] [LIMIT]
#
#   FOLDER  the folder to list (default: Inbox)
#   LIMIT   how many messages to ask for (default: 10)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly: the answer lists NOTHING unless the call has `limit` and `offset`. `nRecords` says how many there are, `nDisplayRecords` how many the answer holds, and `data` is empty with no limit. The script always sends both (offset 0).
# - The id of a message is the same in the Drafts folder of the sender and in the Inbox of the recipient, and it is a 32 character hex text.
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

USAGE="Usage: ./04.mailbox_folders_name_GET.sh [FOLDER] [LIMIT]"
if [ "$#" -lt 0 ] || [ "$#" -gt 2 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
FOLDER="${1:-Inbox}"
LIMIT="${2:-10}"
if [ -z "${FOLDER}" ] || [[ ! "${LIMIT}" =~ ^[1-9][0-9]*$ ]]; then
    printf "FOLDER is '%s' and LIMIT is '%s': a folder name, and a whole number of 1 or more.\n%s\n" "${FOLDER}" "${LIMIT}" "${USAGE}"
    exit 2
fi
ENCODED=$(jq -rn --arg v "${FOLDER}" '$v|@uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "${MAIN_URL}/folders/${ENCODED}" --data-urlencode "limit=${LIMIT}" --data-urlencode "offset=0" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not list the folder %s (HTTP %s): %s\n" "${FOLDER}" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf "%s: %s messages, %s listed.\n" "${FOLDER}" "$(printf '%s' "${BODY}" | jq -r '.nRecords')" "$(printf '%s' "${BODY}" | jq -r '(.data // []) | length')"
printf '%s' "${BODY}" | jq -r '(.data // [])[] | "  \(.id)  \(if .unread then "unread" else "read" end)  from \(.sender.address // "-")  \(.subject)"'
