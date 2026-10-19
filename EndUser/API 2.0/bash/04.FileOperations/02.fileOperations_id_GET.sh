#!/bin/bash
# ==============================================================================
# Script Name: 02.fileOperations_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the state of a file operation, using the
# `/fileOperations/{id}` endpoint: its status, its result, and its error
# message when it failed.
#
# Usage:
# ./02.fileOperations_id_GET.sh OPERATION_ID
#
#   OPERATION_ID  the id POST /fileOperations answered with, as the other
#                 examples in this folder print it
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - The status is the operation's own, not the file's: confirmed directly, an
#   Upload stays IN_PROGRESS after all its content has arrived. The file is
#   complete once its upload has finished; check it with
#   02.Files/10.files_filepath_GET_metadata.sh.
# - A cancelled operation answers 404 (see 05.fileOperations_id_DELETE.sh).
# - Requires `jq`.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ENDUSER_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }
export ST_URL="${ST_URL:-https://${ST_SERVER}:${ST_PORT}/api/v2.0}"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
source "${SCRIPT_DIR}/../ensure_session.sh"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

OPERATION_ID="$1"
if [ -z "${OPERATION_ID}" ]; then
    printf "Usage: ./02.fileOperations_id_GET.sh OPERATION_ID\n"
    exit 2
fi
st_ensure_session

RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/fileOperations/${OPERATION_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "No such operation (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
    exit 1
fi
printf '%s\n' "${BODY}"
printf '%s' "${BODY}" | jq -r '"\n\(.operation) of \(.filePath): \(.status)\(if .errorMsg then " - " + .errorMsg else "" end)"'
