#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Leaves nothing behind: deletes the file and the folder it made (by their exact names, file first), ends the session and removes the cookie jar and the csrfToken file.
#
# Usage:
# ./99.cleanup_DELETE.sh
#
# Risk: write
#
# Notes:
# - It removes only what this use case created, by its exact name.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

# Bottom up: a folder with a file in it cannot be deleted. A name that is not there is fine.
if [ -f "${JAR}" ] || st_session; then
    for name in "${RENAMED}" "${FILE_NAME}"; do
        curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/files/$(st_enc "${FOLDER}/${name}")" \
             -H "accept: application/json" -H "Referer: ${REFERER}"
    done
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/files/$(st_enc "${FOLDER}")" \
         -H "accept: application/json" -H "Referer: ${REFERER}"
    # The file 09 sends with a folder in its name lands in the home folder, not in the folder
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/files/$(st_enc "${LANDED}")" \
         -H "accept: application/json" -H "Referer: ${REFERER}"
fi
rm -rf "${UC_DIR}/downloaded_files"

if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" \
         -H "accept: application/json" -H "Referer: ${REFERER}"
fi
rm -f "${JAR}" "${CSRF_FILE}"
echo "Cleaned up."
