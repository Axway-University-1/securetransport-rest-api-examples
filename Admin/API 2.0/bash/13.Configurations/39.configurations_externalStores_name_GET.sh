#!/bin/bash
# ==============================================================================
# Script Name: 39.configurations_externalStores_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads an external store, using the
# `/configurations/externalStores/{externalStoreName}` endpoint.
#
# Usage:
# ./39.configurations_externalStores_name_GET.sh [NAME]
#
#   NAME  the external store (default example_vault)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The AppRole's secret_id comes back masked.
# - Requires `jq`, which URL-encodes the name and prints the summary.
# - The name is URL-encoded into the path (a name with a space works); one with a / is refused with exit 2 (nothing is sent),
#   as the web server answers 400 to an encoded slash.
# - Confirmed directly: an unknown store is 404 "Cannot find external store with name 'X' or external store configuration is not accessible".
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
NAME="${1:-example_vault}"
# A name with a slash cannot be addressed: the web server answers 400 to an encoded slash
if [[ "${NAME}" == */* ]]; then
    printf "NAME must not hold a /: such a name cannot be addressed in a path.\n"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/externalStores/${ENCODED}" -H "accept: application/json" \
  -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read %s (HTTP %s):\n%s\n" "${NAME}" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '"  \(.name): \(.method) \(.baseUrl)\(.uri), secret at \(.pathPrefix), cached \(.cacheTimeout)s",
  "  login: \(.auth.baseUrl // "-")\(.auth.uri // "")"'
