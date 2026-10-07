#!/bin/bash
# ==============================================================================
# Script Name: 03.daemons_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script updates the SSH daemon configuration using the `/daemons/{name}` endpoint.
# It demonstrates both a valid and an invalid update to the `maxConnections` field,
# and checks the HTTP response code to confirm success or failure.
#
# Usage:
# ./03.daemons_name_PUT.sh
#
# Risk: config - changes the SSH daemon
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The script uses basic authentication and sends JSON payloads via PUT requests.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NAME="ssh"

# Valid update: maxConnections = 10
curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "PUT" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/${NAME}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "{ \"maxConnections\": \"10\", \"preferBouncyCastleProvider\": false, \"banner\": \"This is a SecureTransport REST API test banner.\" }"

# Invalid update: maxConnections = -10
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "PUT" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/${NAME}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "{ \"maxConnections\": \"-10\", \"preferBouncyCastleProvider\": false, \"banner\": \"This is a SecureTransport REST API test banner.\" }")

if [ "${RESPONSE_CODE}" -eq 200 ]; then
    echo "The daemon was successfully updated."
else
    echo "The daemon was not updated. Please check the response code: ${RESPONSE_CODE}"
fi
