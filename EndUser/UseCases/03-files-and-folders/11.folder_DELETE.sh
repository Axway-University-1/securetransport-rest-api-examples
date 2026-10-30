#!/bin/bash
# ==============================================================================
# Script Name: 11.folder_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Deletes the folder. A folder with anything in it is refused with 403, so the files go first and the folder last: this shows the refusal, then empties the folder, then deletes it.
#
# Usage:
# ./11.folder_DELETE.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/07.files_filepath_DELETE.sh.
# - It deletes by exact name, and only the names this use case made. It does not list the folder and delete what it finds.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

URL="${ST_URL}/files/$(st_enc "${FOLDER}")"
# Put one file back, so there is something in the folder to be refused for
LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
echo "left behind" > "${LOCAL}"
curl -k -s -o /dev/null -b "${JAR}" -X POST "${URL}" -F "file=@${LOCAL};filename=${FILE_NAME}" -H "accept: application/json" -H "Referer: ${REFERER}"

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${URL}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Delete the folder with a file in it: HTTP ${code}"
[[ "${code}" == 403 ]] || { echo "Expected 403."; exit 1; }

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${URL}/${FILE_NAME}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Delete the file: HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${URL}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Delete the empty folder: HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
