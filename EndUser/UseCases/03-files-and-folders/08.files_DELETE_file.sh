#!/bin/bash
# ==============================================================================
# Script Name: 08.files_DELETE_file.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Deletes the file (now named as 07 left it). DELETE /files/<folder>/<file> answers 204, and the next read of it is 404, which this checks.
#
# Usage:
# ./08.files_DELETE_file.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/07.files_filepath_DELETE.sh.
# - Deleting a file that is not there is 404, so a second run reports it.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

URL="${ST_URL}/files/$(st_enc "${FOLDER}/${RENAMED}")"
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${URL}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Delete ${FOLDER}/${RENAMED}: HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X GET "${URL}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Read it again: HTTP ${code}"
[[ "${code}" == 404 ]] || { echo "It is still there."; exit 1; }
