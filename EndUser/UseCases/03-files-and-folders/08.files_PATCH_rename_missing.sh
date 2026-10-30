#!/bin/bash
# ==============================================================================
# Script Name: 08.files_PATCH_rename_missing.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Renames a file that is not there. The same PATCH as 07, on the old name that 07 renamed away: the answer is 403, and nothing is changed.
#
# Usage:
# ./08.files_PATCH_rename_missing.sh
#
# Risk: write
#
# Notes:
# - No copy in EndUser/API 2.0/bash: it is 02.Files/13 with a name that is not there.
# - The answer is 403, not 404: a 403 on a rename can mean that the file is missing. Look with a read of the file (05) before you trust the reason.
# - It needs 07 to have renamed the file first.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

BODY=$(jq -n --arg to "/${FOLDER}/${RENAMED}" '[{op: "add", path: "/newFilePath", value: $to}]')
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/files/$(st_enc "${FOLDER}/${FILE_NAME}")" \
       -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
echo "Rename ${FILE_NAME} (renamed away by 07, so not there) to ${RENAMED}: HTTP ${code}"
[[ "${code}" == 403 ]] || { echo "Expected 403."; exit 1; }
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/files/$(st_enc "${FOLDER}/${FILE_NAME}")?metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Is ${FILE_NAME} there? HTTP ${code}"
[ "${code}" = 404 ] || { echo "It is there, so this 403 is about something else, and this step does not show what it should."; exit 1; }
echo "No: the 403 was for a file that is not there."
