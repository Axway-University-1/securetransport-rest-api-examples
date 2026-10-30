#!/bin/bash
# ==============================================================================
# Script Name: 08.fileOperations_POST_multipart.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# The same two-step upload with the content sent as one multipart form: POST /fileOperations declares it, then POST /fileOperations/<id> sends the file.
#
# Usage:
# ./08.fileOperations_POST_multipart.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/04.FileOperations/04.fileOperations_id_POST_multipart.sh.
# - The form carries the name (filename=): without it the file is stored under the name of the local file. The second half shows it, with a local file named like the file it makes.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
st_sample "${LOCAL}" 50000

BODY=$(jq -n --arg path "/${FOLDER}/${MULTIPART_FILE}" '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')
ID=$(curl -k -s -b "${JAR}" -X POST "${ST_URL}/fileOperations" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}" | jq -r '.id // empty' 2>/dev/null)
[ -n "${ID}" ] || { echo "No operation id came back, so nothing was uploaded."; exit 1; }

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/fileOperations/${ID}" -H "accept: application/json" -H "Referer: ${REFERER}" -F "file=@${LOCAL};filename=${MULTIPART_FILE}")
echo "Send the content to operation ${ID}: HTTP ${code}"
[[ "${code}" == 2* ]] || exit 1

# Without filename= the name is the local file's: a local file with a known name shows it
LOCALDIR=$(mktemp -d)
trap 'rm -f "${LOCAL}"; rm -rf "${LOCALDIR}"' EXIT
st_sample "${LOCALDIR}/${LOCALNAME_FILE}" 1000
ID=$(curl -k -s -b "${JAR}" -X POST "${ST_URL}/fileOperations" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" \
     -d "$(jq -n --arg path "/${FOLDER}/${MULTIPART_FILE}" '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')" | jq -r '.id // empty' 2>/dev/null)
[ -n "${ID}" ] || { echo "No operation id came back for the second upload."; exit 1; }
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/fileOperations/${ID}" -H "accept: application/json" -H "Referer: ${REFERER}" -F "file=@${LOCALDIR}/${LOCALNAME_FILE}")
echo "Send the content with no filename= to operation ${ID}: HTTP ${code}"
[[ "${code}" == 2* ]] || exit 1
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/files/$(st_enc "${FOLDER}/${LOCALNAME_FILE}")?metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Is there a file named after the local file (${LOCALNAME_FILE})? HTTP ${code}"
[ "${code}" = 200 ] && echo "Yes: the name of the operation was not used. Always give filename=."
