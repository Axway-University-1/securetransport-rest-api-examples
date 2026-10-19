#!/bin/bash
# ==============================================================================
# Script Name: 03.fileOperations_id_PUT_chunked.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script uploads a file in chunks, using the `/fileOperations` endpoint.
# A large file can then be sent piece by piece, a failed piece sent again, and an
# upload that stopped continued from the piece it stopped at. It demonstrates:
# - Declaring the upload with POST /fileOperations, which answers with an id
# - Sending each chunk with PUT /fileOperations/{id} and a Content-Range header,
#   bytes START-END/SIZE
# - Retrying a chunk that fails, a number of times, before giving up
# - Saying which chunk failed, and continuing from it with --resume
#
# Usage:
# ./03.fileOperations_id_PUT_chunked.sh LOCAL_FILE [FOLDER [CHUNK_SIZE]] [--retries N] [--wait SECONDS] [--resume OPERATION_ID CHUNK]
#
#   LOCAL_FILE  the path of the file to upload, on this machine
#   FOLDER      where to put it, relative to the home folder (default: the home
#               folder). The folder must exist.
#   CHUNK_SIZE  bytes per chunk (default 1048576, 1 MiB)
#   --retries N       how many times a chunk that fails is sent again before the script
#                     gives up (default 3, so 4 attempts in all; 0 for no retry)
#   --wait SECONDS    how long to wait between two attempts at a chunk (default 2)
#   --resume OPERATION_ID CHUNK
#                     do not declare a new upload: carry on with the operation
#                     OPERATION_ID, from the chunk numbered CHUNK (counted from 1). A
#                     failed run prints the line to use. The file and the CHUNK_SIZE
#                     must be the same as in the run that started the upload.
#
# For example:
# ./03.fileOperations_id_PUT_chunked.sh big.iso reports 5242880 --retries 5
# ./03.fileOperations_id_PUT_chunked.sh big.iso reports 5242880 --resume 3f2a-... 7
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - Confirmed directly: each chunk answers 200, and the file is whole after the
#   last one. The operation's own status stays IN_PROGRESS throughout.
# - Confirmed directly: the chunks are taken in order. A chunk sent out of order is refused
#   with 500, and an operation that was left after chunk 1 takes chunk 2 and 3 later and
#   ends with a whole file (its MD5 is the file's). That is what --resume does.
# - A chunk is retried when it fails with anything but 401, 403 or 404: retrying cannot
#   fix those (an expired session, a wrong id), so the script stops at once and says so.
#   The server also answers 500 now and then for a chunk that works the next time.
# - When a chunk fails for good, the script prints its number, the bytes it covers, the
#   answer of the server and the command to continue with. Investigate, fix, run that.
# - END in Content-Range is the last byte of the chunk, not the one after it.
# - Each chunk is cut out of the file with tail and head, on macOS and Linux
#   alike.
# - Exit codes: 0 when the file is whole, 1 when a chunk failed for good (or no operation
#   id came back), 2 when an argument is wrong (nothing is sent).
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

USAGE="Usage: ./03.fileOperations_id_PUT_chunked.sh LOCAL_FILE [FOLDER [CHUNK_SIZE]] [--retries N] [--wait SECONDS] [--resume OPERATION_ID CHUNK]"
RETRIES=3
WAIT=2
RESUME_ID=""
RESUME_CHUNK=""
POSITIONAL=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --retries) RETRIES="$2"; shift 2 || { echo "${USAGE}"; exit 2; } ;;
        --wait)    WAIT="$2"; shift 2 || { echo "${USAGE}"; exit 2; } ;;
        --resume)  RESUME_ID="$2"; RESUME_CHUNK="$3"; shift 3 || { echo "${USAGE}"; exit 2; } ;;
        --*)       echo "${USAGE}"; exit 2 ;;
        *)         POSITIONAL+=("$1"); shift ;;
    esac
done
LOCAL_FILE="${POSITIONAL[0]:-}"
FOLDER="${POSITIONAL[1]:-}"
FOLDER="${FOLDER#/}"
FOLDER="${FOLDER%/}"
CHUNK_SIZE="${POSITIONAL[2]:-1048576}"
if [ -z "${LOCAL_FILE}" ] || [ ! -f "${LOCAL_FILE}" ] || [ "${#POSITIONAL[@]}" -gt 3 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
[[ "${CHUNK_SIZE}" =~ ^[1-9][0-9]*$ ]] || { printf "CHUNK_SIZE must be a whole number: %s\n" "${CHUNK_SIZE}"; exit 2; }
[[ "${RETRIES}" =~ ^[0-9]+$ ]] || { printf "--retries must be a whole number (0 or more): %s\n" "${RETRIES}"; exit 2; }
[[ "${WAIT}" =~ ^[0-9]+$ ]] || { printf "--wait must be a whole number of seconds: %s\n" "${WAIT}"; exit 2; }
if [ -n "${RESUME_ID}" ] || [ -n "${RESUME_CHUNK}" ]; then
    if [ -z "${RESUME_ID}" ] || ! [[ "${RESUME_CHUNK}" =~ ^[1-9][0-9]*$ ]]; then
        printf "--resume takes the operation id and the number of the chunk to start from (1 or more): '%s' '%s'\n" "${RESUME_ID}" "${RESUME_CHUNK}"
        exit 2
    fi
fi

SIZE=$(wc -c < "${LOCAL_FILE}" | tr -d ' ')
if [ "${SIZE}" -eq 0 ]; then
    printf "%s is empty, so there is nothing to send in chunks.\n" "${LOCAL_FILE}"
    exit 2
fi
TOTAL=$(( (SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE ))
FIRST=1
if [ -n "${RESUME_ID}" ]; then
    FIRST="${RESUME_CHUNK}"
    if [ "${FIRST}" -gt "${TOTAL}" ]; then
        printf "There is no chunk %s: with %s bytes in chunks of %s the file has %s.\n" "${FIRST}" "${SIZE}" "${CHUNK_SIZE}" "${TOTAL}"
        exit 2
    fi
fi
st_ensure_session

REMOTE_PATH="/${FOLDER:+${FOLDER}/}$(basename "${LOCAL_FILE}")"

#
# 1. Declare the upload and read the operation id from the response, or carry on with the one given
#
if [ -n "${RESUME_ID}" ]; then
    OPERATION_ID="${RESUME_ID}"
    printf "Continuing operation %s with chunk %s of %s.\n" "${OPERATION_ID}" "${FIRST}" "${TOTAL}"
else
    BODY=$(jq -n --arg path "${REMOTE_PATH}" \
      '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')
    printf "Declaring the upload of %s, %s bytes, in %s chunks of %s bytes...\n" "${REMOTE_PATH}" "${SIZE}" "${TOTAL}" "${CHUNK_SIZE}"
    OPERATION_ID=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/fileOperations" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
      -d "${BODY}" | jq -r '.id // empty' 2>/dev/null)
    if [ -z "${OPERATION_ID}" ]; then
        printf "No operation id came back, so nothing was uploaded.\n"
        exit 1
    fi
    printf "Operation: %s\n" "${OPERATION_ID}"
fi

#
# 2. Send the chunks, each with its own Content-Range, and each tried again when it fails
#
CHUNK=$(mktemp)
ANSWER=$(mktemp)
trap 'rm -f "${CHUNK}" "${ANSWER}"' EXIT
ATTEMPTS=$((RETRIES + 1))
for N in $(seq "${FIRST}" "${TOTAL}"); do
    START=$(( (N - 1) * CHUNK_SIZE ))
    END=$((START + CHUNK_SIZE - 1))
    [ "${END}" -ge "${SIZE}" ] && END=$((SIZE - 1))
    tail -c +"$((START + 1))" "${LOCAL_FILE}" | head -c "$((END - START + 1))" > "${CHUNK}"

    ATTEMPT=1
    while true; do
        printf "Chunk %s of %s, bytes %s-%s/%s, attempt %s of %s... " "${N}" "${TOTAL}" "${START}" "${END}" "${SIZE}" "${ATTEMPT}" "${ATTEMPTS}"
        HTTP_CODE=$(curl -s -k -o "${ANSWER}" -b "${COOKIE}" -X PUT "${ST_URL}/fileOperations/${OPERATION_ID}" \
          -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/octet-stream" \
          -H "Content-Range: bytes ${START}-${END}/${SIZE}" --data-binary "@${CHUNK}" -w "%{http_code}")
        printf "HTTP %s\n" "${HTTP_CODE}"
        case "${HTTP_CODE}" in
            2*) break ;;
            401|403|404) ATTEMPT="${ATTEMPTS}" ;;   # retrying cannot fix a session or an id that is not there
        esac
        if [ "${ATTEMPT}" -ge "${ATTEMPTS}" ]; then
            printf "\nChunk %s of %s failed (bytes %s-%s of %s), after %s attempt(s). The last answer, HTTP %s:\n" "${N}" "${TOTAL}" "${START}" "${END}" "${SIZE}" "${ATTEMPT}" "${HTTP_CODE}"
            cat "${ANSWER}"
            printf "\nChunks 1 to %s are on the server. Find out why chunk %s failed (a refused session or id, 401, 403 or 404, a full\n" "$((N - 1))" "${N}"
            printf "disk, the server unreachable, a 500 in its log), put it right, and send the rest with:\n\n"
            printf "  ./03.fileOperations_id_PUT_chunked.sh %q %q %s --resume %s %s\n" "${LOCAL_FILE}" "${FOLDER}" "${CHUNK_SIZE}" "${OPERATION_ID}" "${N}"
            exit 1
        fi
        printf "  Waiting %s second(s) before trying chunk %s again...\n" "${WAIT}" "${N}"
        sleep "${WAIT}"
        ATTEMPT=$((ATTEMPT + 1))
    done
done
printf "Uploaded %s in %s chunk(s) of %s bytes.\n" "${REMOTE_PATH}" "$((TOTAL - FIRST + 1))" "${CHUNK_SIZE}"
