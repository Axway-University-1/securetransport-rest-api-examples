#!/bin/bash
# ==============================================================================
# Script Name: 05.applications_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script updates an application using the `/applications/{name}` endpoint.
# It demonstrates:
# - Retrieving the full application object
# - Modifying the notes field with a timestamp
# - Sending a PUT request to update the application
#
# Usage:
# ./05.applications_name_PUT.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - PUT replaces the entire object, so all required fields must be preserved.
# - Requires `jq`, which is used to edit the retrieved JSON.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications"
NAME="AccountFilePurge%20Application"

curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "${MAIN_URL}/${NAME}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" > tmp.json
DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

#
# Edit the retrieved object with jq. This targets the notes field itself and
# always produces valid JSON, which a text substitution cannot guarantee.
#
jq --arg notes "New note ${DATE}" '.notes = $notes' \
   tmp.json > tmp.json.new && mv tmp.json.new tmp.json

curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "PUT" "${MAIN_URL}/${NAME}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d @tmp.json

# Remove the temporary API response
rm -f tmp.json
