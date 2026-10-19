#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Leaves nothing behind: ends the session, revokes the API key of this use case if one is left (by its id), and removes the cookie jar and the state files.
#
# Usage:
# ./99.cleanup_DELETE.sh
#
# Risk: write
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" \
         -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
fi
rm -f "${JAR}" "${CSRF_FILE}"
# A key of this use case that is still there is revoked, by its id: the other keys are not touched
if [ -s "${APIKEY_ID_FILE}" ]; then
    bash "${UC_DIR}/10.apikey_DELETE.sh"
fi
rm -f "${APIKEY_FILE}" "${APIKEY_ID_FILE}"
echo "Cleaned up."
