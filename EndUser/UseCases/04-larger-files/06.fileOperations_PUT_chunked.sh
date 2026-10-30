#!/bin/bash
# ==============================================================================
# Script Name: 06.fileOperations_PUT_chunked.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Uploads a file in pieces. POST /fileOperations declares the upload and returns an id; each piece is a PUT to that id with a Content-Range header that says which bytes it is. The way to send a file too big for one request, or to resume.
#
# Usage:
# ./06.fileOperations_PUT_chunked.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/04.FileOperations/03.fileOperations_id_PUT_chunked.sh.
# - The file is 250000 bytes sent in pieces of 100000.
# - Content-Range is bytes START-END/TOTAL, both ends included, counted from 0.
# - The pieces go in order. The operation stays IN_PROGRESS after the last one, so the proof that the file arrived whole is its MD5 (04 and st_md5calc), checked at the end. 07 shows what happens out of order.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

CHUNK_SIZE=100000
LOCAL=$(mktemp); CHUNK=$(mktemp)
trap 'rm -f "${LOCAL}" "${CHUNK}"' EXIT
st_sample "${LOCAL}" 250000
SIZE=$(wc -c < "${LOCAL}" | tr -d ' ')

BODY=$(jq -n --arg path "/${FOLDER}/${CHUNKED_FILE}" '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')
ID=$(curl -k -s -b "${JAR}" -X POST "${ST_URL}/fileOperations" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}" | jq -r '.id // empty' 2>/dev/null)
[ -n "${ID}" ] || { echo "No operation id came back, so nothing was uploaded."; exit 1; }

START=0
while [ "${START}" -lt "${SIZE}" ]; do
    END=$((START + CHUNK_SIZE - 1))
    [ "${END}" -ge "${SIZE}" ] && END=$((SIZE - 1))
    tail -c +"$((START + 1))" "${LOCAL}" | head -c "$((END - START + 1))" > "${CHUNK}"
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PUT "${ST_URL}/fileOperations/${ID}" -H "accept: application/json" -H "Referer: ${REFERER}" \
           -H "Content-Type: application/octet-stream" -H "Content-Range: bytes ${START}-${END}/${SIZE}" --data-binary "@${CHUNK}")
    echo "Bytes ${START}-${END}/${SIZE}: HTTP ${code}"
    [[ "${code}" == 2* ]] || { echo "A piece was refused, so the upload stops."; exit 1; }
    START=$((END + 1))
done
echo "Uploaded ${FOLDER}/${CHUNKED_FILE} in pieces of ${CHUNK_SIZE} bytes."
st_md5calc "/${FOLDER}/${CHUNKED_FILE}" || exit 1
[ "${SERVER_MD5}" = "$(st_md5 "${LOCAL}")" ] || { echo "The server holds ${SERVER_SIZE} bytes with MD5 ${SERVER_MD5}, not the MD5 of the file that was sent."; exit 1; }
echo "Verified: the server holds ${SERVER_SIZE} bytes with the MD5 of the local file."
