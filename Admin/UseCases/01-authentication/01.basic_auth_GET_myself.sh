#!/bin/bash
# ==============================================================================
# Script Name: 01.basic_auth_GET_myself.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Basic authentication on a single call. The administrator's name and password travel with the request itself (curl -u), so no login and no session are needed: ask who you are, and the server checks the password on this call alone.
#
# Usage:
# ./01.basic_auth_GET_myself.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/02.Introduction/03.myself_GET.sh, with the call made on its own.
# - curl -u user:password is the same as the header Authorization: Basic base64(user:password). It is the shortest way to one call, and most Admin examples use it: it sends the password every time.
# - A call that carries its own credentials needs no csrfToken, even for a write.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

result=$(curl -k -s -w "%{http_code}" -u "${ST_USER}:${ST_PASSWORD}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
echo "${result%???}" | jq -r '"You are " + .loginName + ", role " + .roleName + (if .isLimited then " (limited)" else "" end)' 
