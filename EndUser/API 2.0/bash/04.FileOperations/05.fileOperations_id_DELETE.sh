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
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Confirmed directly: the DELETE answers 200, and a GET of the operation
#   afterwards answers 404.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

OPERATION_ID="$1"
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

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
