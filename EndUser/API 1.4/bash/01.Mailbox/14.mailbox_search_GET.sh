#!/bin/bash
# ==============================================================================
# Script Name: 14.mailbox_search_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script searches the mailbox with `GET /api/v1.4/mailbox/search`: every message of the user, sent, received and drafts, by a part of its subject.
#
# Usage:
# ./14.mailbox_search_GET.sh [SUBJECT] [LIMIT]
#
#   SUBJECT  a part of the subject to look for (default: every message)
#   LIMIT    how many to ask for (default: 10)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - NOT CONFIRMED to find a message: the reference itself has a known issue ("does not search successfully all the messages"), and on the lab a search by a subject that is in the Inbox found nothing (nRecords 0). Use 04 to list a folder.
# - Like the folder listing, the call needs `limit` and `offset`: the script sends both.
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

USAGE="Usage: ./14.mailbox_search_GET.sh [SUBJECT] [LIMIT]"
if [ "$#" -lt 0 ] || [ "$#" -gt 2 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
SUBJECT="${1:-}"
LIMIT="${2:-10}"
if [[ ! "${LIMIT}" =~ ^[1-9][0-9]*$ ]]; then
    printf "LIMIT is '%s': a whole number of 1 or more.\n%s\n" "${LIMIT}" "${USAGE}"
    exit 2
fi
QUERY=()
[ -n "${SUBJECT}" ] && QUERY=(--data-urlencode "subject=${SUBJECT}")

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "${MAIN_URL}/search" "${QUERY[@]}" --data-urlencode "limit=${LIMIT}" --data-urlencode "offset=0" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not search (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf "%s messages found, %s listed.\n" "$(printf '%s' "${BODY}" | jq -r '.nRecords')" "$(printf '%s' "${BODY}" | jq -r '(.data // []) | length')"
printf '%s' "${BODY}" | jq -r '(.data // [])[] | "  \(.id)  \(.folder)  \(.subject)"'
