#!/bin/bash
# ==============================================================================
# Script Name: 10.apikey_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-19
# Location: Sofia
# ==============================================================================
# Description:
# Revokes the key 08 made, by its id: DELETE /administrators/<name>/api-keys/<id>. Then proves it: the same key is refused with 401. The other keys of the administrator are not touched.
#
# Usage:
# ./10.apikey_DELETE.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/21.Administrators/10.administrators_name_apiKeys_keyId_DELETE.sh.
# - It revokes the one key whose id 08 saved, and nothing else.
# - A revoked key stops working at once. It is also gone from the list (21.Administrators/09), so a key that stays unused for good is best revoked.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
if [ ! -s "${APIKEY_ID_FILE}" ]; then
    echo "There is no API key to revoke: 08.apikey_POST.sh has not been run."
    exit 2
fi
ID=$(cat "${APIKEY_ID_FILE}")
KEY=$(cat "${APIKEY_FILE}" 2>/dev/null)
ADMIN_ENC=$(printf '%s' "${ST_USER}" | jq -Rr @uri)

code=$(curl -k -s -o /dev/null -w "%{http_code}" -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${ST_URL}/administrators/${ADMIN_ENC}/api-keys/${ID}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "Revoke key ${ID}: HTTP ${code}"
[[ "${code}" == 20* ]] || exit 1
rm -f "${APIKEY_FILE}" "${APIKEY_ID_FILE}"

if [ -n "${KEY}" ]; then
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -H "SECURETRANSPORT-API-KEY: ${KEY}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
    echo "The revoked key: HTTP ${code}"
    if [[ "${code}" == 401 ]]; then
        echo "The key is dead."
    else
        echo "The revoked key still works."
        exit 1
    fi
fi
