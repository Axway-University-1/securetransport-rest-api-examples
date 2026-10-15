#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Leaves nothing behind: ends the session and removes the cookie jar and the csrfToken file.
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

if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" \
         -H "accept: application/json" -H "Referer: ${REFERER}"
fi
rm -f "${JAR}" "${CSRF_FILE}"
echo "Cleaned up."
