#!/bin/bash
# ==============================================================================
# Script Name: 09.apikey_GET_myself.sh
# Author: Plamen Milenkov
# Created: 2026-10-19
# Location: Sofia
# ==============================================================================
# Description:
# The same call as 01, with the key and nothing else: no user, no password, no cookie, no csrfToken. The header SECURETRANSPORT-API-KEY authenticates the request on its own. Then a write is tried with the read-only key, and refused with 403.
#
# Usage:
# ./09.apikey_GET_myself.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/21.Administrators/09.administrators_name_apiKeys_GET.sh.
# - Run 08 first (it saves the key in state.local.apikey).
# - No session means no csrfToken: a key is the one way in that needs neither, for GET and for the writes its permissions allow.
# - A method the key's permissions do not cover answers a plain-text 403; a revoked or unknown key a plain-text 401, "Authentication required.".
# - The refused write sends nothing that could change the server: it is a PATCH of /myself with the key that may only read.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
if [ ! -s "${APIKEY_FILE}" ]; then
    echo "There is no API key yet: run 08.apikey_POST.sh first (or 00.run_all.sh)."
    exit 2
fi
KEY=$(cat "${APIKEY_FILE}")

result=$(curl -k -s -w "%{http_code}" -H "SECURETRANSPORT-API-KEY: ${KEY}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "A read with the key alone: HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
echo "${result%???}" | jq -r '"You are " + .loginName + ", role " + .roleName'

code=$(curl -k -s -o /dev/null -w "%{http_code}" -H "SECURETRANSPORT-API-KEY: ${KEY}" -X PATCH "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" \
       -H "Content-Type: application/json" -d '[]')
echo "A write with the read-only key: HTTP ${code}"
if [[ "${code}" == 403 ]]; then
    echo "Refused, as it should be: the key may only read."
else
    echo "Expected 403."
    exit 1
fi
