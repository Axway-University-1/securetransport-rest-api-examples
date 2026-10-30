#!/bin/bash
# ==============================================================================
# Script Name: 07.files_PATCH_rename.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Renames the file. PATCH /files/<folder>/<file> with a one-line JSON patch that sets /newFilePath to the new full path. 204 means done.
#
# Usage:
# ./07.files_PATCH_rename.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/13.files_filepath_PATCH_rename.sh. 12 does the same with a PUT.
# - The new path is the whole path, with a leading slash: /<folder>/<new name>.
# - It renames a file that is there: a name that is not there is refused with 403 (08 shows it).
# - A file uploaded a moment ago can be refused with 403 too, for a few seconds: this tries again, up to 10 times, one second apart. If it is still 403 after that, the file is probably not there.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

BODY=$(jq -n --arg to "/${FOLDER}/${RENAMED}" '[{op: "add", path: "/newFilePath", value: $to}]')
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/files/$(st_enc "${FOLDER}/${FILE_NAME}")" \
           -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
    [ "${code}" = 403 ] || break
    echo "Rename ${FILE_NAME} to ${RENAMED}: HTTP 403, trying again in a second (${attempt} of 10)."
    sleep 1
done
echo "Rename ${FILE_NAME} to ${RENAMED}: HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
