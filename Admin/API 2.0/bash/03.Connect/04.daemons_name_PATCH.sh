#!/bin/bash
# ==============================================================================
# Script Name: 04.daemons_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script sends PATCH requests to update specific fields of the SSH daemon
# using the `/daemons/{name}` endpoint. It demonstrates how to patch individual
# attributes such as `maxConnections`, `preferBouncyCastleProvider`, and `banner`.
#
# Usage:
# ./04.daemons_name_PATCH.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The script uses JSON Patch format and basic authentication.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NAME="ssh"

printf "Patching the daemon maxConnections...\n"
curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "PATCH" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/${NAME}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "[{ \"op\": \"replace\", \"path\": \"/maxConnections\", \"value\": 4 }]"

printf "Patching the daemon preferBouncyCastleProvider...\n"
curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "PATCH" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/${NAME}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "[{ \"op\": \"replace\", \"path\": \"/preferBouncyCastleProvider\", \"value\": true }]"

printf "Patching the daemon banner...\n"
curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "PATCH" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/${NAME}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "[{ \"op\": \"replace\", \"path\": \"/banner\", \"value\": \"New banner\" }]"
