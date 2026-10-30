#!/bin/bash
# ==============================================================================
# Script Name: 09.files_POST_bulk.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Uploads several files in a loop, one POST each, and stops at the first refusal with a count of what went. A loop of the same call is what a bulk upload is.
#
# Usage:
# ./09.files_POST_bulk.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/05.files_filepath_POST_v2.sh.
# - The three files are the names in BULK_FILES (lib.sh).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
sent=0
for name in ${BULK_FILES}; do
    st_sample "${LOCAL}" 2000
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/files/$(st_enc "${FOLDER}")" \
           -F "file=@${LOCAL};filename=${name}" -H "accept: application/json" -H "Referer: ${REFERER}")
    echo "Upload ${name}: HTTP ${code}"
    [[ "${code}" == 2* ]] || { echo "Stopped after ${sent} files."; exit 1; }
    sent=$((sent + 1))
done
echo "Uploaded ${sent} files."
