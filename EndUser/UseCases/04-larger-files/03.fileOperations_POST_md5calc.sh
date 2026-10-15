#!/bin/bash
# ==============================================================================
# Script Name: 03.fileOperations_POST_md5calc.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Asks the server for the MD5 of a file it already holds, and compares it with the local copy. POST /fileOperations starts an MD5Calc operation, and GET /fileOperations/<id> is followed until it is DONE.
#
# Usage:
# ./03.fileOperations_POST_md5calc.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/04.FileOperations/01.fileOperations_POST_md5calc.sh.
# - It is an operation because a big file takes time: the status goes IN_PROGRESS, then DONE (or an error), and it waits at most 30 seconds.
# - It needs 02 to have uploaded the file first.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
st_sample "${LOCAL}" 100000 md5
BODY=$(jq -n --arg path "/${FOLDER}/${MD5_FILE}" '{operation: "MD5Calc", filePath: $path}')
OPERATION=$(curl -k -s -b "${JAR}" -X POST "${ST_URL}/fileOperations" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
ID=$(echo "${OPERATION}" | jq -r '.id // empty' 2>/dev/null)
if [ -z "${ID}" ]; then
    echo "No operation id came back: ${OPERATION}"
    exit 1
fi

STATUS=$(echo "${OPERATION}" | jq -r '.status')
waited=0
while [ "${STATUS}" = "IN_PROGRESS" ] || [ "${STATUS}" = "WAITING" ]; do
    [ "${waited}" -ge 30 ] && { echo "Still ${STATUS} after 30 seconds."; exit 1; }
    sleep 1
    waited=$((waited + 1))
    OPERATION=$(curl -k -s -b "${JAR}" -X GET "${ST_URL}/fileOperations/${ID}" -H "accept: application/json" -H "Referer: ${REFERER}")
    STATUS=$(echo "${OPERATION}" | jq -r '.status')
done
[ "${STATUS}" = "DONE" ] || { echo "The operation ended ${STATUS}: ${OPERATION}"; exit 1; }

SERVER=$(echo "${OPERATION}" | jq -r '.result.md5Checksum')
echo "The server: $(echo "${OPERATION}" | jq -r '.result.fileSize') bytes, MD5 ${SERVER}"
echo "Here:       $(wc -c < "${LOCAL}" | tr -d ' ') bytes, MD5 $(st_md5 "${LOCAL}")"
[ "${SERVER}" = "$(st_md5 "${LOCAL}")" ] && echo "They match." || { echo "They do NOT match."; exit 1; }
