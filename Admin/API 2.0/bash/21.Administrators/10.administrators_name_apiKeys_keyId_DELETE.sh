#!/bin/bash
# ==============================================================================
# Script Name: 10.administrators_name_apiKeys_keyId_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script revokes an administrator's API keys, using the
# `/administrators/{name}/api-keys/{keyId}` endpoint. A revoked key stops
# working at once.
#
# Usage:
# ./10.administrators_name_apiKeys_keyId_DELETE.sh [KEY_ID]
#
#   KEY_ID  the key to revoke (default: every key of example_admin)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The administrator is example_admin, which 02.administrators_POST.sh creates.
# - Confirmed directly: a revoke answers 204.
# - Requires `jq`, which reads the key ids.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="example_admin"

if [ -n "$1" ]; then
    KEY_IDS="$1"
else
    KEY_IDS=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ADMIN}/api-keys" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.[].id')
fi
if [ -z "${KEY_IDS}" ]; then
    printf "%s has no API keys.\n" "${ADMIN}"
    exit 0
fi

for KEY_ID in ${KEY_IDS}; do
    printf "Revoking the key %s of %s... " "${KEY_ID}" "${ADMIN}"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE \
      "${MAIN_URL}/${ADMIN}/api-keys/${KEY_ID}" -H "accept: */*" -H "${REFERER_HEADER}")
    printf "HTTP %s\n" "${HTTP_CODE}"
    [ "${HTTP_CODE}" = "204" ] || exit 1
done
