#!/bin/bash
# ==============================================================================
# Script Name: 16.configurations_database_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the database configuration, using the
# `/configurations/database` endpoint: the database type, host, port, name and
# user the server connects with.
#
# Usage:
# ./16.configurations_database_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The password never comes back.
# - PUT /configurations/database repoints the server at another database; it
#   has no example here, as a wrong value stops the server. Use the Admin UI's
#   database settings for that, after a test with
#   17.configurations_database_operations_POST_test.sh.
# - GET and PUT /configurations/database/{componentType}, for the server log and
#   the transfer log databases, apply to Oracle only.
# - Requires `jq`, which prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/database" -H "accept: application/json" \
  -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '"  \(.databaseType) \(if .isInternalDB then "(embedded)" else "(external)" end) at \(.host):\(.port), database \(.databaseName), user \(.username)", "  running: \(.databaseRunning), secure connection: \(.secureConnectionEnabled)"'
