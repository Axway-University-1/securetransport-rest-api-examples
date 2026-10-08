#!/bin/bash
# ==============================================================================
# Script Name: 44.configurations_externalStores_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes an external store, using the
# `/configurations/externalStores/{externalStoreName}` endpoint.
#
# Usage:
# ./44.configurations_externalStores_name_DELETE.sh [NAME]
#
#   NAME  the external store (default example_vault)
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Anything that fetches its secrets from the store stops working: only ever
#   point it at a store you created.
# - The store is read first and what is deleted is printed (its address and cache timeout), so that it can be added again with
#   38.configurations_externalStores_POST.sh. A store that cannot be read stops the script (exit 1) before anything is deleted.
# - Requires `jq`, which URL-encodes the name and reads the store.
# - The name is URL-encoded into the path (a name with a space works); one with a / is refused with exit 2 (nothing is sent),
#   as the web server answers 400 to an encoded slash.
# - Confirmed directly: a delete is 204 with no body. A name that is not a store is 400 (not 404) on the delete, "Cannot delete External Store
#   with name: X. Cannot find External Store or External Store configuration is not accessible", and 404 on the read.
# - Exit codes: 0 when the store was deleted (204), 1 when the server refuses or the store cannot be read, 2 when the name is wrong (nothing sent).
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

# Read it first, to say what is being deleted
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/externalStores/${ENCODED}" -H "accept: application/json" \
  -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the external store %s (HTTP %s), so nothing was deleted.\n" "${NAME}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi

printf "Deleting the external store %s (%s)...\n" "${NAME}" "$(printf '%s' "${RESPONSE}" | jq -r '"\(.baseUrl)\(.uri), cached \(.cacheTimeout)s"')"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/externalStores/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
