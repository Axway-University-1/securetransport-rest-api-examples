#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Leaves nothing behind: ends the session if one is still open (07), and removes
# the cookie jar and the csrfToken file. This use case creates no object on the server.
#
# Usage:
# ./99.cleanup_DELETE.sh
#
# Risk: write
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

if [ -f "${JAR}" ]; then
    bash "${UC_DIR}/07.logout_DELETE.sh" >/dev/null 2>&1
fi
rm -f "${JAR}" "${CSRF_FILE}"
echo "Cleaned up."
