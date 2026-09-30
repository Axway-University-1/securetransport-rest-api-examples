#!/bin/bash
# ==============================================================================
# Script Name: 12.servers_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a server using the `/servers/{name}` endpoint.
# It demonstrates:
# - A direct DELETE request for a server by name
# - A conditional DELETE request after checking server existence
#
# Usage:
# ./12.servers_name_DELETE.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The server name must be valid and exist in the system.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NAME="SSH_TEST_SERVER_1"
printf "Deleting server '${NAME}'...\n"
curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "DELETE" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json"
printf "Done\n"

NAME="SSH_TEST_SERVER_2"
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
-H "accept: */*" -H "${REFERER_HEADER}")
if [ "${RESPONSE_CODE}" == "200" ]; then
    printf "Server exists. Deleting server '${NAME}'...\n"
    curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "DELETE" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
    -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json"
    printf "\nDone\n"
else
    echo "Server does not exist."
fi
