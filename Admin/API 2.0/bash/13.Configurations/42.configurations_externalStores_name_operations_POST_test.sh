#!/bin/bash
# ==============================================================================
# Script Name: 42.configurations_externalStores_name_operations_POST_test.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script tests an external store, using the
# `/configurations/externalStores/{externalStoreName}/operations` endpoint with
# operation=test: the server logs in and fetches one secret, and reports each
# step.
#
# Usage:
# ./42.configurations_externalStores_name_operations_POST_test.sh SECRET_PATH [NAME]
#
#   SECRET_PATH  a secret to fetch, for example example/db
#   NAME  the external store (default example_vault)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is 200 whatever the outcome; fetchStatus,
#   connectionStatus and authenticationStatus say what worked, and message and
#   solution what did not. The secret's values come back masked, ****.
# - In a certificate or a site, ${fetch(externalStore, ...)} reads a secret at
#   run time; see the option descriptions that mention it.
# - tests/integration/lib/dummy_servers.py has a FakeVault that can stand in for
#   a HashiCorp Vault to try these examples against.
# - Requires `jq`, which URL-encodes the name, builds the body and prints the outcome.
# - The name is URL-encoded into the path (a name with a space works); one with a / is refused with exit 2 (nothing is sent),
#   as the web server answers 400 to an encoded slash.
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
[ -n "${SECRET_PATH}" ] || { printf "Usage: ./42.configurations_externalStores_name_operations_POST_test.sh SECRET_PATH [NAME]\n"; exit 2; }
# A name with a slash cannot be addressed: the web server answers 400 to an encoded slash
if [[ "${NAME}" == */* ]]; then
    printf "NAME must not hold a /: such a name cannot be addressed in a path.\n"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')
BODY=$(jq -cn --arg path "${SECRET_PATH}" '{secretPath: $path}')

printf "Testing %s with the secret %s...\n" "${NAME}" "${SECRET_PATH}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/externalStores/${ENCODED}/operations?operation=test" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '
  "  connection: \(.connectionStatus // "-"), login: \(.authenticationStatus // "-"), fetch: \(.fetchStatus // "-")",
  (if .response.jsonData then "  the secret holds: \(.response.jsonData | keys | join(", "))" else empty end),
  (if .message then "  \(.message)" else empty end)'
printf '%s' "${RESPONSE}" | jq -e '.fetchStatus == "Success"' >/dev/null
