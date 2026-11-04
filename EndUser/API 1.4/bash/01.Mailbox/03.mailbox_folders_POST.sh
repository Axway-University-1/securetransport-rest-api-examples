#!/bin/bash
# ==============================================================================
# Script Name: 03.mailbox_folders_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script makes a mailbox folder with `POST /api/v1.4/mailbox/folders`. The call takes form data, not JSON.
#
# Usage:
# ./03.mailbox_folders_POST.sh NAME
#
#   NAME  the name of the new folder
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly: the answer is 204 with no body. A folder that is not empty cannot be deleted (see 13).
# - Tried, and refused: renaming a folder (`PUT /mailbox/folders/{oldName}/name`, form field `name`) answered 403 "Cannot rename folder", "Permission denied" for a folder of the user. No example is given.
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

USAGE="Usage: ./03.mailbox_folders_POST.sh NAME"
if [ "$#" -lt 1 ] || [ "$#" -gt 1 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
FOLDER="$1"
if [ -z "${FOLDER}" ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/folders" --data-urlencode "name=${FOLDER}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf "Could not make the folder %s (HTTP %s): %s\n" "${FOLDER}" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
printf "The folder %s was made (HTTP 204).\n" "${FOLDER}"
