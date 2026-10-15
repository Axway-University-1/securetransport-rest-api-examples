#!/bin/bash
# ==============================================================================
# Script Name: 02.files_POST_upload.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Uploads a file into the folder. POST /files/<folder> with the content as a multipart form; the filename given in the form is the name it gets. The content is made here, so there is nothing to prepare.
#
# Usage:
# ./02.files_POST_upload.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/04.files_filepath_POST.sh, with the folder in the URL.
# - The folder goes in the URL, not in the filename: a filename with a folder in it is cut down to its last part, and the file lands in the home folder.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
printf 'First version of the notes.\n' > "${LOCAL}"

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "$ST_URL/files/$(st_enc "${FOLDER}")" \
       -F "file=@${LOCAL};filename=${FILE_NAME}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Upload ${FOLDER}/${FILE_NAME}: HTTP ${code}"
[[ "${code}" == 20* ]] || exit 1
