#!/bin/bash
# ==============================================================================
# Script Name: 07.folder_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Removes the file and then the folder, by their exact names. A folder with a file in it is refused (403), so the file goes first.
#
# Usage:
# ./07.folder_DELETE.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/07.files_filepath_DELETE.sh.
# - Run 06 first, or the folder is still shared when it goes: deleting a shared folder is for its owner, and the other user loses it.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

URL="${ST_URL}/files/$(st_enc "${FOLDER}")"
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${URL}/${FILE_NAME}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Delete the file: HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${URL}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Delete the folder: HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
