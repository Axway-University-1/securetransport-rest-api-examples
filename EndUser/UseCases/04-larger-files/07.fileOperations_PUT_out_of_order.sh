#!/bin/bash
# ==============================================================================
# Script Name: 07.fileOperations_PUT_out_of_order.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# What the server does with a piece sent out of order. Declares an upload of 250000 bytes, sends the last piece first (500), then lists the folder: the file is there, with a size that looks like a file, and its MD5 is not the MD5 of the local file. Only the MD5 tells that the file is not whole.
#
# Usage:
# ./07.fileOperations_PUT_out_of_order.sh
#
# Risk: write
#
# Notes:
# - No copy in EndUser/API 2.0/bash: it joins 04.FileOperations/02 and 03 (a piece out of order) with the checksum of 04.FileOperations/01.
# - A file in the listing, even one with a size close to the declared one, is not proof of a whole file (the size on the lab was 215985 for a declared 250000, and 250000 on an earlier run). The MD5 is the proof.
# - After a failure like this one, delete the file and send it again from the first piece.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

CHUNK_SIZE=100000
LOCAL=$(mktemp); CHUNK=$(mktemp)
trap 'rm -f "${LOCAL}" "${CHUNK}"' EXIT
st_sample "${LOCAL}" 250000
SIZE=$(wc -c < "${LOCAL}" | tr -d ' ')

BODY=$(jq -n --arg path "/${FOLDER}/${ORDER_FILE}" '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')
ID=$(curl -k -s -b "${JAR}" -X POST "${ST_URL}/fileOperations" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}" | jq -r '.id // empty' 2>/dev/null)
[ -n "${ID}" ] || { echo "No operation id came back, so nothing was uploaded."; exit 1; }

# The last piece first: bytes 200000-249999
START=$((2 * CHUNK_SIZE))
END=$((SIZE - 1))
tail -c +"$((START + 1))" "${LOCAL}" > "${CHUNK}"
SENT=$(wc -c < "${CHUNK}" | tr -d ' ')
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PUT "${ST_URL}/fileOperations/${ID}" -H "accept: application/json" -H "Referer: ${REFERER}" \
       -H "Content-Type: application/octet-stream" -H "Content-Range: bytes ${START}-${END}/${SIZE}" --data-binary "@${CHUNK}")
echo "Bytes ${START}-${END}/${SIZE} (the last piece) first: HTTP ${code}"
[[ "${code}" == 2* ]] && { echo "The server took a piece out of order, so there is nothing to show."; exit 1; }

code=$(curl -k -s -o "${CHUNK}" -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/files/$(st_enc "${FOLDER}")" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "List the folder: HTTP ${code}"
[ "${code}" = 200 ] || exit 1
LISTED=$(jq -r --arg n "${ORDER_FILE}" '.files[]? | select(.fileName == $n) | .size' "${CHUNK}")
if [ -z "${LISTED}" ]; then
    echo "${ORDER_FILE} is not listed: nothing was stored."
    exit 0
fi
echo "${ORDER_FILE} is listed, ${LISTED} bytes (declared: ${SIZE}, sent: ${SENT})."
st_md5calc "/${FOLDER}/${ORDER_FILE}" || exit 1
if [ "${SERVER_MD5}" = "$(st_md5 "${LOCAL}")" ]; then
    echo "The MD5 matches: the file is whole."
else
    echo "The MD5 is ${SERVER_MD5}, not that of the local file: the listing says ${LISTED} bytes and still the file is not whole. Delete it and send it again, in order."
fi
