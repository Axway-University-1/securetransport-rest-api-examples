#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Leaves nothing behind: stops sharing the folder, deletes the file and the folder it made (by their exact names), ends the session and removes the cookie jar and the csrfToken file.
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

# Unshare first, then the file, then the folder. A name that is not there is fine.
if [ -f "${JAR}" ] || st_session; then
    URL="${ST_URL}/files/$(st_enc "${FOLDER}")"
    curl -k -s -o /dev/null -b "${JAR}" -X PATCH "${URL}" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" \
         -d '[{"op":"remove","path":"/sharedDirectoryProperties"}]'
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${URL}/${FILE_NAME}" -H "accept: application/json" -H "Referer: ${REFERER}"
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${URL}" -H "accept: application/json" -H "Referer: ${REFERER}"
fi

if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" \
         -H "accept: application/json" -H "Referer: ${REFERER}"
fi
rm -f "${JAR}" "${CSRF_FILE}"
echo "Cleaned up."
