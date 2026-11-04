#!/bin/bash
# ==============================================================================
# Script Name: 01.validation_validPath_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script asks the server whether a path may be used, with `POST /api/v1.4/validation/validPath` of the Admin API 1.4. The API 2.0 has no such call.
# The server checks the path the way it checks the folders you type in the Administration Tool: the path must be absolute, must hold no `..`, and must not be on the
# server's list of unsafe paths.
#
# Usage:
# ./01.validation_validPath_POST.sh PATH
#
#   PATH  the path to check, for example /data/inbox
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - The call is a POST with form data (not JSON), and it changes nothing. With JSON it answers 415.
# - Confirmed directly on 5.5-20260924: 200 with an empty body means the path is valid, and the folder does not have to exist (/no/such/dir is valid).
#   A path with spaces is valid. 403 means refused, with the reason in validationErrors: "Folder name is not absolute", "Folder name relative path sequence" (a `..`),
#   "Path cannot be in the unsafe paths list" (/etc is refused). An empty path is 400 "may not be empty".
# - The script exits 0 for a valid path, 1 for a refused one, 2 for wrong use.
# - Requires `jq` to read the reason of a refusal.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ADMIN_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v1.4/validation/validPath"
USAGE="Usage: ./01.validation_validPath_POST.sh PATH"
if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
CHECKED_PATH="$1"

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" --data-urlencode "path=${CHECKED_PATH}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" = "200" ]; then
    printf "%s is a valid path (HTTP 200).\n" "${CHECKED_PATH}"
    exit 0
fi
printf "%s is refused (HTTP %s): " "${CHECKED_PATH}" "${HTTP_CODE}"
printf '%s' "${RESPONSE}" | jq -r '(.validationErrors[0] // .message // .)' 2>/dev/null || printf '%s\n' "${RESPONSE}"
exit 1
