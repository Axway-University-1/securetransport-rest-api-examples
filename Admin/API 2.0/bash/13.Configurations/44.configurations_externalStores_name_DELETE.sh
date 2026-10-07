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
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Anything that fetches its secrets from the store stops working: only ever
#   point it at a store you created.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
NAME="${1:-example_vault}"

printf "Deleting the external store %s...\n" "${NAME}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/externalStores/${NAME}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
