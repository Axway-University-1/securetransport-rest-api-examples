#!/bin/bash
# ==============================================================================
# Script Name: 04.fileOperations_id_POST_multipart.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script uploads a file in two steps, sending the content as a multipart
# form, using the `/fileOperations` endpoint. It demonstrates:
# - Declaring the upload with POST /fileOperations, which answers with an id
# - Sending the whole file with POST /fileOperations/{id}, multipart/form-data
#
# Usage:
# ./04.fileOperations_id_POST_multipart.sh LOCAL_FILE [FOLDER]
#
#   LOCAL_FILE  the file to upload
#   FOLDER      where to put it, relative to the home folder (default: the home
#               folder). The folder must exist.
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - The content is a multipart form here; 02.Files/08.fileOperations_POST_upload.sh
#   PUTs it as application/octet-stream instead. Confirmed directly: POST with
#   octet-stream answers 415, POST with a multipart form answers 200.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

LOCAL_FILE="$1"
FOLDER="${2:-}"
FOLDER="${FOLDER#/}"
FOLDER="${FOLDER%/}"
if [ -z "${LOCAL_FILE}" ] || [ ! -f "${LOCAL_FILE}" ]; then
    printf "Usage: ./04.fileOperations_id_POST_multipart.sh LOCAL_FILE [FOLDER]\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

REMOTE_PATH="/${FOLDER:+${FOLDER}/}$(basename "${LOCAL_FILE}")"

#
# 1. Declare the upload, and read the operation id from the response
#
BODY=$(jq -n --arg path "${REMOTE_PATH}" \
  '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')
printf "Declaring the upload of %s...\n" "${REMOTE_PATH}"
OPERATION_ID=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/fileOperations" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" | jq -r '.id // empty' 2>/dev/null)
if [ -z "${OPERATION_ID}" ]; then
    printf "No operation id came back, so nothing was uploaded.\n"
    exit 1
fi

#
# 2. Send the content to that operation, as a multipart form
#
printf "Sending the content to operation %s...\n" "${OPERATION_ID}"
HTTP_CODE=$(curl -s -k -o /dev/null -b "${COOKIE}" -X POST "${ST_URL}/fileOperations/${OPERATION_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -F "file=@${LOCAL_FILE}" -w "%{http_code}")
printf "HTTP %s\n" "${HTTP_CODE}"
case "${HTTP_CODE}" in
    2*) printf "Uploaded %s.\n" "${REMOTE_PATH}" ;;
    *)  exit 1 ;;
esac
