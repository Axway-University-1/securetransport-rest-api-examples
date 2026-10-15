#!/bin/bash
# ==============================================================================
# Script Name: 05.fileOperations_POST_multipart.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# The same two-step upload with the content sent as one multipart form: POST /fileOperations declares it, then POST /fileOperations/<id> sends the file.
#
# Usage:
# ./05.fileOperations_POST_multipart.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/04.FileOperations/04.fileOperations_id_POST_multipart.sh.
# - The form carries the name (filename=): without it the file is stored under the name of the local file, here a temporary one.
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
