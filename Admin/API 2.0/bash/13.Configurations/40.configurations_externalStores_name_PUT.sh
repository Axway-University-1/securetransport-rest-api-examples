#!/bin/bash
# ==============================================================================
# Script Name: 40.configurations_externalStores_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces an external store, using the
# `/configurations/externalStores/{externalStoreName}` endpoint with PUT: it
# reads the store, changes how long the server waits for an answer
# (readTimeout), and sends the whole store back.
#
# Usage:
# ./40.configurations_externalStores_name_PUT.sh SECONDS [NAME]
#
#   SECONDS  the new readTimeout
#   NAME  the external store (default example_vault)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Changing a store clears the secrets the server cached from it.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which edits the store.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
SECONDS_WAIT="$1"
NAME="${2:-example_vault}"
[[ "${SECONDS_WAIT}" =~ ^[1-9][0-9]*$ ]] || { printf "Usage: ./40.configurations_externalStores_name_PUT.sh SECONDS [NAME]\n"; exit 2; }

STORE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/externalStores/${NAME}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${STORE}" | jq -e '.name' >/dev/null 2>&1; then
    printf "There is no external store %s.\n" "${NAME}"
    exit 1
fi
printf "readTimeout of %s is now %s.\n" "${NAME}" "$(printf '%s' "${STORE}" | jq -r '.readTimeout')"
BODY=$(printf '%s' "${STORE}" | jq -c --argjson seconds "${SECONDS_WAIT}" '.readTimeout = $seconds')

printf "Setting it to %s...\n" "${SECONDS_WAIT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/externalStores/${NAME}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
