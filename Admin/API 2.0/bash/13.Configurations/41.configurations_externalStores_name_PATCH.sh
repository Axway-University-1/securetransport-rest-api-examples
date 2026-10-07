#!/bin/bash
# ==============================================================================
# Script Name: 41.configurations_externalStores_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes how long the server caches the secrets it reads from an
# external store (cacheTimeout), using the
# `/configurations/externalStores/{externalStoreName}` endpoint with PATCH.
#
# Usage:
# ./41.configurations_externalStores_name_PATCH.sh SECONDS [NAME]
#
#   SECONDS  the new cacheTimeout; 0 does not cache
#   NAME  the external store (default example_vault)
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Changing a store clears the secrets the server cached from it.
# - Confirmed directly: a success answers 204, with no body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
SECONDS_CACHE="$1"
NAME="${2:-example_vault}"
[[ "${SECONDS_CACHE}" =~ ^[0-9]+$ ]] || { printf "Usage: ./41.configurations_externalStores_name_PATCH.sh SECONDS [NAME]\n"; exit 2; }

printf "Caching the secrets of %s for %s seconds...\n" "${NAME}" "${SECONDS_CACHE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/externalStores/${NAME}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "[{\"op\":\"replace\",\"path\":\"/cacheTimeout\",\"value\":${SECONDS_CACHE}}]" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
