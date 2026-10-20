#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Ends the session and removes the cookie jar and the csrfToken file. Nothing can be removed from the account: a secret question cannot be cleared once it is set.
#
# Usage:
# ./99.cleanup_DELETE.sh
#
# Risk: write
#
# Notes:
# - This use case creates no object. If 03 was run, the account keeps the question it set.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" \
         -H "accept: application/json" -H "Referer: ${REFERER}"
fi
rm -f "${JAR}" "${CSRF_FILE}"
echo "Cleaned up."
