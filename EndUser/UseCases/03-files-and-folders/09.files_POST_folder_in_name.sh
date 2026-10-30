#!/bin/bash
# ==============================================================================
# Script Name: 09.files_POST_folder_in_name.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Puts the folder in the filename instead of the URL, which does not work: the server keeps only the last part of the name, and the file lands in the home folder, not in the folder. The script shows where it landed and removes it.
#
# Usage:
# ./09.files_POST_folder_in_name.sh
#
# Risk: write
#
# Notes:
# - No copy in EndUser/API 2.0/bash: it is 02.Files/04 with a path in the form field filename=.
# - The folder goes in the URL (02). A filename with a folder in it is cut down to its last part, with no error: the answer is 201.
# - The file is removed again in this script, by its exact name; 99 removes it too if a run stopped halfway.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
printf 'Where did I land?\n' > "${LOCAL}"

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/files" \
       -F "file=@${LOCAL};filename=${FOLDER}/${LANDED}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Upload with the filename ${FOLDER}/${LANDED}: HTTP ${code}"
[[ "${code}" == 20* ]] || exit 1

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/files/$(st_enc "${FOLDER}/${LANDED}")?metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "In the folder, ${FOLDER}/${LANDED}: HTTP ${code}"
code2=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/files/$(st_enc "${LANDED}")?metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "In the home folder, ${LANDED}: HTTP ${code2}"
[ "${code2}" = 200 ] && [ "${code}" != 200 ] || { echo "It did not land in the home folder only."; exit 1; }
echo "It landed in the home folder: the folder of the name was dropped. Put the folder in the URL."

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/files/$(st_enc "${LANDED}")" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Delete it from the home folder: HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
