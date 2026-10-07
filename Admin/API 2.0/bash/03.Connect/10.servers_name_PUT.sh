#!/bin/bash
# ==============================================================================
# Script Name: 10.servers_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script updates an SSH server configuration using the PUT method via curl.
# It demonstrates:
# - A direct update with a new port
# - A full update using retrieved server data with modified fields
#
# Usage:
# ./10.servers_name_PUT.sh
#
# Risk: config - changes a protocol server
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The PUT method replaces the entire object, so all required fields must be included.
# - Requires `jq`, which is used to edit the retrieved JSON.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NAME="SSH_TEST_SERVER_1"
NEW_PORT=$((8022 + RANDOM % 10))

# Direct PUT update
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "PUT" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d "{ \"serverName\": \"${NAME}\", \"protocol\": \"ssh\", \"port\": ${NEW_PORT} }"

# Retrieve and modify server configuration
NEW_PORT=$((8022 + RANDOM % 10))
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" > tmp.json

#
# Edit the retrieved object with jq. This targets the exact fields and always
# produces valid JSON, which a text substitution cannot guarantee.
#
jq --argjson newPort "${NEW_PORT}" \
   '.port = $newPort | .clientPasswordAuth = "default"' \
   tmp.json > tmp.json.new && mv tmp.json.new tmp.json

curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "PUT" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d @tmp.json

# Remove the temporary API response
rm -f tmp.json
