#!/bin/bash
# ==============================================================================
# Script Name: 09.administrators_name_apiKeys_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists an administrator's API keys, using the
# `/administrators/{name}/api-keys` endpoint, and shows a call made with one.
# It demonstrates:
# - The keys' ids, expiry, permissions and last use
# - Authenticating with the SECURETRANSPORT-API-KEY header alone
#
# Usage:
# ./09.administrators_name_apiKeys_GET.sh [KEY]
#
#   KEY  a key 08.administrators_name_apiKeys_POST.sh printed, to call
#        GET /myself with it (optional)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The administrator is example_admin, which 02.administrators_POST.sh creates.
# - The list never holds the keys themselves, only their ids.
# - Confirmed directly: with a key, GET /myself answers as the key's
#   administrator, with no -u and no session; a method the key's permissions do
#   not cover answers 403, "This API key does not have permission to perform
#   DELETE requests."; a revoked or expired key answers 401, in plain text,
#   "Authentication required."
# - Requires `jq`, which prints one key per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="example_admin"
KEY="$1"

printf "The API keys of %s: id, valid until, permissions, last used:\n" "${ADMIN}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ADMIN}/api-keys" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.[] | "  \(.id)  \(.expiresAt)  \(.permissions | join(","))  \(.lastAccessedAt // "never")\(if .expired then "  EXPIRED" else "" end)"'

if [ -n "${KEY}" ]; then
    printf "\nWho the key logs in as, with no password and no session:\n"
    RESPONSE=$(curl -s -k -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" \
      -H "SECURETRANSPORT-API-KEY: ${KEY}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "  The key was refused (HTTP %s): %s\n" "${HTTP_CODE}" "${RESPONSE}"
        exit 1
    fi
    printf '%s' "${RESPONSE}" | jq -r '"  \(.loginName), role \(.roleName)"'
fi
