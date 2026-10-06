#!/bin/bash
# ==============================================================================
# Script Name: 03.fileOperations_id_PUT_chunked.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script uploads a file in chunks, using the `/fileOperations` endpoint.
# A large file can then be sent piece by piece, and a failed piece sent again.
# It demonstrates:
# - Declaring the upload with POST /fileOperations, which answers with an id
# - Sending each chunk with PUT /fileOperations/{id} and a Content-Range header,
#   bytes START-END/SIZE
#
# Usage:
# ./03.fileOperations_id_PUT_chunked.sh LOCAL_FILE [FOLDER [CHUNK_SIZE]]
#
#   LOCAL_FILE  the file to upload
#   FOLDER      where to put it, relative to the home folder (default: the home
#               folder). The folder must exist.
#   CHUNK_SIZE  bytes per chunk (default 1048576, 1 MiB)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Confirmed directly: each chunk answers 200, and the file is whole after the
#   last one. The operation's own status stays IN_PROGRESS throughout.
# - END in Content-Range is the last byte of the chunk, not the one after it.
# - Each chunk is cut out of the file with tail and head, on macOS and Linux
#   alike.
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
CHUNK_SIZE="${3:-1048576}"
if [ -z "${LOCAL_FILE}" ] || [ ! -f "${LOCAL_FILE}" ]; then
    printf "Usage: ./03.fileOperations_id_PUT_chunked.sh LOCAL_FILE [FOLDER [CHUNK_SIZE]]\n"
    exit 2
fi
[[ "${CHUNK_SIZE}" =~ ^[1-9][0-9]*$ ]] || { printf "CHUNK_SIZE must be a whole number: %s\n" "${CHUNK_SIZE}"; exit 2; }
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

SIZE=$(wc -c < "${LOCAL_FILE}" | tr -d ' ')
REMOTE_PATH="/${FOLDER:+${FOLDER}/}$(basename "${LOCAL_FILE}")"

#
# 1. Declare the upload, and read the operation id from the response
#
BODY=$(jq -n --arg path "${REMOTE_PATH}" \
  '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')
printf "Declaring the upload of %s, %s bytes...\n" "${REMOTE_PATH}" "${SIZE}"
OPERATION_ID=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/fileOperations" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" | jq -r '.id // empty' 2>/dev/null)
if [ -z "${OPERATION_ID}" ]; then
    printf "No operation id came back, so nothing was uploaded.\n"
    exit 1
fi

#
# 2. Send the chunks, each with its own Content-Range
#
CHUNK=$(mktemp)
trap 'rm -f "${CHUNK}"' EXIT
START=0
while [ "${START}" -lt "${SIZE}" ]; do
    END=$((START + CHUNK_SIZE - 1))
    [ "${END}" -ge "${SIZE}" ] && END=$((SIZE - 1))
    tail -c +"$((START + 1))" "${LOCAL_FILE}" | head -c "$((END - START + 1))" > "${CHUNK}"

    printf "Sending bytes %s-%s/%s... " "${START}" "${END}" "${SIZE}"
    HTTP_CODE=$(curl -s -k -o /dev/null -b "${COOKIE}" -X PUT "${ST_URL}/fileOperations/${OPERATION_ID}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/octet-stream" \
      -H "Content-Range: bytes ${START}-${END}/${SIZE}" --data-binary "@${CHUNK}" -w "%{http_code}")
    printf "HTTP %s\n" "${HTTP_CODE}"
    case "${HTTP_CODE}" in
        2*) ;;
        *) printf "The chunk was refused, so the upload stops here.\n"; exit 1 ;;
    esac
    START=$((END + 1))
done
printf "Uploaded %s in chunks of %s bytes.\n" "${REMOTE_PATH}" "${CHUNK_SIZE}"
