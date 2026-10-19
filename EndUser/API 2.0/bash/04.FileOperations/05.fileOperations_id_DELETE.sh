#!/bin/bash
# ==============================================================================
# Script Name: 05.fileOperations_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script cancels a file operation, using the `/fileOperations/{id}`
# endpoint with DELETE. Without an id, it shows the whole cycle: it declares an
# upload, cancels it before any content is sent, and confirms it is gone.
#
# Usage:
# ./05.fileOperations_id_DELETE.sh [OPERATION_ID]
#
#   OPERATION_ID  the operation to cancel (default: a new upload of
#                 cancelled_upload.txt, declared here to be cancelled)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - Confirmed directly: the DELETE answers 200, and a GET of the operation
#   afterwards answers 404.
# - Requires `jq`, which builds the body.
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
st_ensure_session

if [ -z "${OPERATION_ID}" ]; then
    printf "Declaring an upload of /cancelled_upload.txt, to cancel it...\n"
    OPERATION_ID=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/fileOperations" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
      -d '{"operation":"Upload","filePath":"/cancelled_upload.txt"}' | jq -r '.id // empty' 2>/dev/null)
    if [ -z "${OPERATION_ID}" ]; then
        printf "No operation id came back.\n"
        exit 1
    fi
fi

printf "Cancelling operation %s...\n" "${OPERATION_ID}"
HTTP_CODE=$(curl -s -k -o /dev/null -b "${COOKIE}" -X DELETE "${ST_URL}/fileOperations/${OPERATION_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "%{http_code}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "200" ] || exit 1

AFTER=$(curl -s -k -o /dev/null -b "${COOKIE}" -X GET "${ST_URL}/fileOperations/${OPERATION_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "%{http_code}")
if [ "${AFTER}" = "404" ]; then
    printf "Cancelled: the operation is gone.\n"
else
    printf "The operation still answers HTTP %s.\n" "${AFTER}"
    exit 1
fi
