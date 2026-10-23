#!/bin/bash
# ==============================================================================
# Script Name: 08.fileOperations_POST_upload.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script uploads a file in two steps, using the `/fileOperations`
# endpoint. Unlike the multipart upload in 04.files_filepath_POST.sh, it sets
# the path the file gets on the server, and the transfer mode. It demonstrates:
# - Declaring the upload with POST /fileOperations, which answers with an id
# - Sending the content to that id with PUT /fileOperations/{id}, as
#   application/octet-stream
#
# Usage:
# ./08.fileOperations_POST_upload.sh [LOCAL_FILE] [FOLDER]
#
#   LOCAL_FILE  the file to upload (default test.txt, next to this script)
#   FOLDER      where to put it, relative to the home folder (default: the
#               home folder itself). The folder must exist. See
#               02.files_name_POST_folder.sh.
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - The content is sent with PUT. A POST to the same id answers 415.
# - transferMode BINARY sends the bytes as they are. ASCII is the other mode.
# - Requires `jq`, which builds the body and reads the id.
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

LOCAL_FILE="${1:-${SCRIPT_DIR}/test.txt}"
FOLDER="${2:-}"
FOLDER="${FOLDER#/}"
FOLDER="${FOLDER%/}"

if [ ! -f "${LOCAL_FILE}" ]; then
    printf "There is no file '%s' to upload.\n" "${LOCAL_FILE}"
    exit 1
fi

REMOTE_PATH="/${FOLDER:+${FOLDER}/}$(basename "${LOCAL_FILE}")"
st_ensure_session

#
# 1. Declare the upload, and read the operation id from the response
#
printf "Declaring the upload of %s...\n" "${REMOTE_PATH}"
BODY=$(jq -n --arg path "${REMOTE_PATH}" \
  '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')
RESPONSE=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/fileOperations" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}")
OPERATION_ID=$(printf '%s' "${RESPONSE}" | jq -r '.id // empty' 2>/dev/null)

#
# 2. Send the content to that operation
#
if [ -z "${OPERATION_ID}" ]; then
    printf "No operation id came back, so nothing was uploaded. The response was:\n%s\n" "${RESPONSE}"
    exit 1
fi
printf "Sending the content to operation %s...\n" "${OPERATION_ID}"
HTTP_CODE=$(curl -s -k -o /dev/null -b "${COOKIE}" -X PUT "${ST_URL}/fileOperations/${OPERATION_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/octet-stream" -w "%{http_code}" \
  --data-binary "@${LOCAL_FILE}")
printf "HTTP %s\n" "${HTTP_CODE}"
[[ "${HTTP_CODE}" == 2* ]] || exit 1
