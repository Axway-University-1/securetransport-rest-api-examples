#!/bin/bash
# ==============================================================================
# Script Name: 06.files_POST_overwrite.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Updates the file: uploading it again under the same name replaces its content (201 again). Then it reads the file to show the new content, and the size changes.
#
# Usage:
# ./06.files_POST_overwrite.sh
#
# Risk: write
#
# Notes:
# - There is no separate update call for the content: POST /files/<folder> with the same filename overwrites it. (A PUT of raw bytes is refused with 415.)
# - Copied from EndUser/API 2.0/bash/02.Files/04.files_filepath_POST.sh, with the read-back of 03 added.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
printf 'Second version of the notes, longer than the first one.\n' > "${LOCAL}"

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/files/$(st_enc "${FOLDER}")" \
       -F "file=@${LOCAL};filename=${FILE_NAME}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Upload again: HTTP ${code}"
[[ "${code}" == 20* ]] || exit 1
echo "Now it reads:"
curl -k -s -b "${JAR}" -X GET "${ST_URL}/files/$(st_enc "${FOLDER}/${FILE_NAME}")" -H "accept: application/json" -H "Referer: ${REFERER}" | sed 's/^/  /' 
