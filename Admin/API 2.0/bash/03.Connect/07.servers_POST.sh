#!/bin/bash
# ==============================================================================
# Script Name: 07.servers_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script creates new server entries using the `/servers` endpoint.
# It demonstrates:
# - Creating a minimal server with name and protocol
# - Duplicating an existing server by modifying its configuration
#
# Usage:
# ./07.servers_POST.sh
#
# Risk: config - adds protocol servers, which open ports
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The serverName must be unique.
# - Supported protocols: ftp, ssh, http, as2, pesit.
# - Requires `jq`, which is used to edit the retrieved JSON.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# Create a minimal SSH server
NAME="SSH_TEST_SERVER_1"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "POST" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "{ \"serverName\": \"${NAME}\", \"protocol\": \"ssh\" }"

# Duplicate an existing server with modifications
NEW_NAME="SSH_TEST_SERVER_2"
NEW_PORT=$((8022 + RANDOM % 10))

printf "Creating a new server with the name: %s and port: %d...\n" "${NEW_NAME}" "${NEW_PORT}"

# Retrieve existing server config
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" > tmp.json

# Modify serverName and port
#
# Edit the retrieved object with jq. This targets the exact fields and always
# produces valid JSON, which a text substitution cannot guarantee.
#
jq --arg newName "${NEW_NAME}" --argjson newPort "${NEW_PORT}" \
   '.serverName = $newName | .port = $newPort | .clientPasswordAuth = "default"' \
   tmp.json > tmp.json.new && mv tmp.json.new tmp.json

# Create new server with modified config
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "POST" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d @tmp.json

# Remove the temporary API response
rm -f tmp.json
