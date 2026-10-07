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
# - Logging in, and keeping both the session cookie and the csrfToken header
# - Declaring the upload with POST /fileOperations, which answers with an id
# - Sending the content to that id with PUT /fileOperations/{id}, as
#   application/octet-stream
# - Logging out again
#
# Usage:
# ./08.fileOperations_POST_upload.sh [LOCAL_FILE [FOLDER]]
#
#   LOCAL_FILE  the file to upload (default test.txt, next to this script)
#   FOLDER      where to put it, relative to the home folder (default: the
#               home folder itself). The folder must exist. See
#               02.files_name_POST_folder.sh.
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It logs in and out on its own, so 01.Authenticate is not needed first.
# - The content is sent with PUT. A POST to the same id answers 415.
# - transferMode BINARY sends the bytes as they are. ASCII is the other mode.
# - Requires `jq`, which builds the body and reads the id.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

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

COOKIE=$(mktemp)
HEADERS=$(mktemp)

#
# Log in. The csrfToken comes back as a response header.
#
LOGIN_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" -D "${HEADERS}" --cookie-jar "${COOKIE}" \
  -H "Authorization: Basic ${ST_BASIC_AUTH}" -X POST "${ST_URL}/myself" \
  -H "accept: application/json" -H "${REFERER_HEADER}")
CSRF_TOKEN=$(grep -i '^csrfToken:' "${HEADERS}" | awk '{print $2}' | tr -d '\r')
rm -f "${HEADERS}"

if [ "${LOGIN_CODE}" != "200" ]; then
    printf "Login failure: HTTP %s\n" "${LOGIN_CODE}"
    rm -f "${COOKIE}"
    exit 1
fi

#
# 1. Declare the upload, and read the operation id from the response
#
printf "Declaring the upload of %s...\n" "${REMOTE_PATH}"
BODY=$(jq -n --arg path "${REMOTE_PATH}" \
  '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')
RESPONSE=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/fileOperations" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}" \
  -H "Content-Type: application/json" -d "${BODY}")
OPERATION_ID=$(printf '%s' "${RESPONSE}" | jq -r '.id // empty' 2>/dev/null)

#
# 2. Send the content to that operation
#
if [ -z "${OPERATION_ID}" ]; then
    printf "No operation id came back, so nothing was uploaded. The response was:\n%s\n" "${RESPONSE}"
else
    printf "Sending the content to operation %s...\n" "${OPERATION_ID}"
    curl -s -k -b "${COOKIE}" -X PUT "${ST_URL}/fileOperations/${OPERATION_ID}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}" \
      -H "Content-Type: application/octet-stream" -w "\nHTTP %{http_code}\n" \
      --data-binary "@${LOCAL_FILE}"
fi

#
# Log out, and remove the session
#
curl -s -k -o /dev/null -b "${COOKIE}" -X DELETE "${ST_URL}/myself" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}"
rm -f "${COOKIE}"

[ -n "${OPERATION_ID}" ]
