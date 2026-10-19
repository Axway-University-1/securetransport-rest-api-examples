#!/bin/bash
# ==============================================================================
# Script Name: 08.apikey_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-19
# Location: Sofia
# ==============================================================================
# Description:
# A third way in, for automation: an API key. POST /administrators/<name>/api-keys makes one for the administrator, valid for 1 day and allowed to read only (GET and HEAD). The key is shown in this answer once and kept here in state.local.apikey; the server stores only a hash.
#
# Usage:
# ./08.apikey_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/21.Administrators/08.administrators_name_apiKeys_POST.sh, for the administrator the settings log in as.
# - Creating a key needs credentials, here Basic authentication: a key cannot make its own.
# - An administrator holds at most 2 keys (a third is 409). The key this script makes is revoked by 10, or by 99, by its id: it never touches the others.
# - validityDays or expiresAt, not both (400). permissions is read, write and delete: write is POST, PUT and PATCH.
# - The key is a secret: state.local.apikey is ignored by git, and removed by 10 and 99.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

# One key at a time: a key left from an earlier run is revoked first, by its id
if [ -s "${APIKEY_ID_FILE}" ]; then
    echo "A key of an earlier run (id $(cat "${APIKEY_ID_FILE}")) is still here: revoking it first."
    bash "${UC_DIR}/10.apikey_DELETE.sh"
fi

ADMIN_ENC=$(printf '%s' "${ST_USER}" | jq -Rr @uri)
BODY=$(jq -n '{validityDays: 1, permissions: ["read"]}')
result=$(curl -k -s -w "\n%{http_code}" -u "${ST_USER}:${ST_PASSWORD}" -X POST "${ST_URL}/administrators/${ADMIN_ENC}/api-keys" \
         -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
code="${result##*$'\n'}"
body="${result%$'\n'*}"
echo "HTTP ${code}"
if [[ "${code}" != 201 ]]; then
    echo "${body}"
    [[ "${code}" == 409 ]] && echo "An administrator holds at most 2 API keys: revoke one (21.Administrators/10.administrators_name_apiKeys_keyId_DELETE.sh) and run this again."
    exit 1
fi
KEY=$(echo "${body}" | jq -r '.key // empty')
ID=$(echo "${body}" | jq -r '.id // empty')
if [ -z "${KEY}" ] || [ -z "${ID}" ]; then
    echo "The answer holds no key or no id."
    exit 1
fi
umask 077
printf '%s' "${KEY}" > "${APIKEY_FILE}"
printf '%s' "${ID}" > "${APIKEY_ID_FILE}"
echo "${body}" | jq -r '"Key id \(.id), valid until \(.expiresAt), permissions \(.permissions | join(", "))"'
echo "The key itself is saved in $(basename "${APIKEY_FILE}") (it is not shown again, here or by the server)."
