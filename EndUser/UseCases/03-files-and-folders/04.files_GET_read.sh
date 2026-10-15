#!/bin/bash
# ==============================================================================
# Script Name: 04.files_GET_read.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Reads the content of the file: GET /files/<folder>/<file> returns the bytes. This one prints them, and saves a copy next to the script (downloaded_files/) to show where a script would keep one.
#
# Usage:
# ./04.files_GET_read.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/03.files_filepath_GET.sh.
# - A missing file is 404, with a message about the file size and type.
# - curl -o writes the body to disk and -w reports the status of the same call.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

mkdir -p "${UC_DIR}/downloaded_files"
code=$(curl -k -s -L -w "%{http_code}" -b "${JAR}" -o "${UC_DIR}/downloaded_files/${FILE_NAME}" \
       -X GET "${ST_URL}/files/$(st_enc "${FOLDER}/${FILE_NAME}")" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Read ${FOLDER}/${FILE_NAME}: HTTP ${code}"
if [[ "${code}" != 200 ]]; then
    echo "Upload it first with 02.files_POST_upload.sh."
    rm -f "${UC_DIR}/downloaded_files/${FILE_NAME}"
    exit 1
fi
echo "Content:"
sed 's/^/  /' "${UC_DIR}/downloaded_files/${FILE_NAME}"
