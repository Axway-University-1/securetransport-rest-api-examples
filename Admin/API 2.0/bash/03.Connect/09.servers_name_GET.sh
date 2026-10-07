#!/bin/bash
# ==============================================================================
# Script Name: 09.servers_name_GET.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves information about a specific server using the `/servers/{name}` endpoint.
# It demonstrates:
# - A full GET request for a server by name
# - A filtered GET request using the `fields` parameter (requires `protocol`)
#
# Usage:
# ./09.servers_name_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The `fields` parameter must be used in combination with `protocol`.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

SERVER_NAME="SSH_TEST_SERVER_1"

# Full server details
printf "\nGetting ${SERVER_NAME}...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${SERVER_NAME}" -H "accept: application/json" -H "${REFERER_HEADER}"

# Filtered fields (requires protocol)
printf "\nGetting ${SERVER_NAME} with applied fields...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${SERVER_NAME}?fields=isActive,port&protocol=ssh" -H "accept: application/json" -H "${REFERER_HEADER}"
