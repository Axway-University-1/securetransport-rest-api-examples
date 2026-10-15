#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Leaves nothing behind: ends the session and removes the cookie jar and the csrfToken file. This use case creates no object on the server.
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
echo "Cleaned up."
