#!/bin/bash
# ==============================================================================
# Script Name: 01.basic_auth_GET_myself.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Basic authentication on a single call. The user name and password travel with
# the request itself (curl -u), so no login and no session are needed: ask who
# you are, and the server checks the password on this call alone.
#
# Usage:
# ./01.basic_auth_GET_myself.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/01.myself_GET.sh, with the session
#   replaced by Basic authentication.
# - curl -u "user:password" is the same as the header
#   "Authorization: Basic base64(user:password)", which curl builds for you. It is
#   simple, and sends the password every time.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

result=$(curl -k -s -w "%{http_code}" -u "${ST_USER}:${ST_PASSWORD}" -X GET "${ST_URL}/myself" \
         -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
echo "${result%???}" | jq -r '"You are " + .name + " (" + .type + ")"' 2>/dev/null || echo "${result%???}"
[[ "${code}" == 200 ]] || exit 1
