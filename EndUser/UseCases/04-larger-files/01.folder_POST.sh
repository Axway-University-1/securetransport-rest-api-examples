#!/bin/bash
# ==============================================================================
# Script Name: 01.folder_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Creates the folder this use case works in (the same call as in 03-files-and-folders/01). If it is there already, nothing is done.
#
# Usage:
# ./01.folder_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/02.files_name_POST_folder.sh.
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
