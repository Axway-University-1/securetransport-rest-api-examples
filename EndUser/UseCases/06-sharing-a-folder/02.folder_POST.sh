#!/bin/bash
# ==============================================================================
# Script Name: 02.folder_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Creates the folder to share, with one file in it. If the folder is there already, it is used as it is.
#
# Usage:
# ./02.folder_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/02.files_name_POST_folder.sh and 04.files_filepath_POST.sh.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

ENC=$(st_enc "${FOLDER}")
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -G "${ST_URL}/files/${ENC}" --data-urlencode "metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}")
if [[ "${code}" != 200 ]]; then
    BODY=$(jq -n '{isDirectory: true, isRegularFile: false, isSymbolicLink: false, isOther: false, isShared: false}')
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/files/${ENC}" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
    echo "Create '${FOLDER}': HTTP ${code}"
    [[ "${code}" == 20* ]] || exit 1
else
    echo "The folder '${FOLDER}' already exists."
fi

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
printf 'Notes for the people this folder is shared with.\n' > "${LOCAL}"
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/files/${ENC}" \
       -F "file=@${LOCAL};filename=${FILE_NAME}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Upload ${FOLDER}/${FILE_NAME}: HTTP ${code}"
[[ "${code}" == 20* ]] || exit 1
