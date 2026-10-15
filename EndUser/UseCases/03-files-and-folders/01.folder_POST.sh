#!/bin/bash
# ==============================================================================
# Script Name: 01.folder_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Creates the folder this use case works in. POST /files/<name> with a body that says it is a directory. If the folder is there already, it says so and does nothing: creating over an existing folder is refused with 409.
#
# Usage:
# ./01.folder_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/02.files_name_POST_folder.sh.
# - The body is what makes it a folder: without it the server answers 400 "File information is missing".
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

ENC=$(st_enc "${FOLDER}")
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -G "${ST_URL}/files/${ENC}" --data-urlencode "metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}")
if [[ "${code}" == 200 ]]; then
    echo "The folder '${FOLDER}' already exists. Nothing to create."
    exit 0
fi

BODY=$(jq -n '{isDirectory: true, isRegularFile: false, isSymbolicLink: false, isOther: false, isShared: false}')
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/files/${ENC}" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
echo "Create '${FOLDER}': HTTP ${code}"
[[ "${code}" == 20* ]] || exit 1
