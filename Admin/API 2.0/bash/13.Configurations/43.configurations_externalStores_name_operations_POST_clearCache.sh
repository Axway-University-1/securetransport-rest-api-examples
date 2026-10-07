#!/bin/bash
# ==============================================================================
# Script Name: 43.configurations_externalStores_name_operations_POST_clearCache.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script clears a secret the server cached from an external store, using
# the `/configurations/externalStores/{externalStoreName}/operations` endpoint
# with operation=clearCache: the next use fetches it again, for example after
# the secret was rotated in the vault.
#
# Usage:
# ./43.configurations_externalStores_name_operations_POST_clearCache.sh SECRET_PATH [NAME]
#
#   SECRET_PATH  the secret, for example example/db
#   NAME  the external store (default example_vault)
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is 200, "Cache was cleared successfully for
#   external store ... and secret path ...".
# - Requires `jq`, which builds the body and prints the answer.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
SECRET_PATH="$1"
NAME="${2:-example_vault}"
[ -n "${SECRET_PATH}" ] || { printf "Usage: ./43.configurations_externalStores_name_operations_POST_clearCache.sh SECRET_PATH [NAME]\n"; exit 2; }
BODY=$(jq -cn --arg path "${SECRET_PATH}" '{secretPath: $path}')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/externalStores/${NAME}/operations?operation=clearCache" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
printf '%s' "${RESPONSE}" | jq -r '.message // .' 2>/dev/null || printf '%s\n' "${RESPONSE}"
[ "${HTTP_CODE}" = "200" ]
