#!/bin/bash
# ==============================================================================
# Script Name: 13.mailbox_folders_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes an empty mailbox folder with `DELETE /api/v1.4/mailbox/folders/{name}`.
#
# Usage:
# ./13.mailbox_folders_name_DELETE.sh NAME
#
#   NAME  the folder to delete
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly: the answer is 200 {"info": "Deletion was successful"}. A folder that holds a message is refused: 403 "Unable to remove folder ... because it is not empty." Move the messages out (11) or delete them (12) first.
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

USAGE="Usage: ./13.mailbox_folders_name_DELETE.sh NAME"
if [ "$#" -lt 1 ] || [ "$#" -gt 1 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
FOLDER="$1"
if [ -z "${FOLDER}" ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
ENCODED=$(jq -rn --arg v "${FOLDER}" '$v|@uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/folders/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not delete the folder %s (HTTP %s): %s\n" "${FOLDER}" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf "HTTP 200: %s\n" "$(printf '%s' "${BODY}" | jq -r '.info // .')"
