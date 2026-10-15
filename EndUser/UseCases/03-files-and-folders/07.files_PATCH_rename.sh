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
# - It renames a file that is there: a name that is not there is refused with 403.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

BODY=$(jq -n --arg to "/${FOLDER}/${RENAMED}" '[{op: "add", path: "/newFilePath", value: $to}]')
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/files/$(st_enc "${FOLDER}/${FILE_NAME}")" \
       -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
echo "Rename ${FILE_NAME} to ${RENAMED}: HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
