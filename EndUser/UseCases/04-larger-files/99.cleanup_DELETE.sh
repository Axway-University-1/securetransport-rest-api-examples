#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Leaves nothing behind: deletes the files and the folder it made (by their exact names, files first), ends the session and removes the cookie jar and the csrfToken file.
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
    for name in "${MD5_FILE}" "${WRONG_FILE}" "${TEXT_ASCII_FILE}" "${TEXT_BINARY_FILE}" "${CHUNKED_FILE}" "${ORDER_FILE}" "${MULTIPART_FILE}" "${LOCALNAME_FILE}" ${BULK_FILES}; do
        curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/files/$(st_enc "${FOLDER}/${name}")" \
             -H "accept: application/json" -H "Referer: ${REFERER}"
    done
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/files/$(st_enc "${FOLDER}")" \
         -H "accept: application/json" -H "Referer: ${REFERER}"
fi

if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" \
         -H "accept: application/json" -H "Referer: ${REFERER}"
fi
rm -f "${JAR}" "${CSRF_FILE}"
echo "Cleaned up."
