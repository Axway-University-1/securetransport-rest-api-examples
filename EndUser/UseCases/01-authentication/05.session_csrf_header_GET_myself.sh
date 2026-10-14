#!/bin/bash
# ==============================================================================
# Script Name: 05.session_csrf_header_GET_myself.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# The session cookie plus the csrfToken the login returned, sent back as the
# csrfToken header. A server can require it on every call that changes
# something (POST, PUT, DELETE), so a script that writes should send it.
#
# Usage:
# ./05.session_csrf_header_GET_myself.sh
#
# Risk: read
#
# Notes:
# - A GET does not need it, and the lab does not enforce it on writes either,
#   but the habit costs one header, and a server that does enforce it answers
#   a write without it with 403.
# - Run 03 first (it saves the token in state.local.csrf).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_need_session

TOKEN=$(cat "${CSRF_FILE}" 2>/dev/null)
if [ -z "${TOKEN}" ]; then
    echo "03 saved no csrfToken (the server did not send one), so there is nothing to add."
    exit 1
fi

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself" \
       -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: ${TOKEN}")
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || exit 1
