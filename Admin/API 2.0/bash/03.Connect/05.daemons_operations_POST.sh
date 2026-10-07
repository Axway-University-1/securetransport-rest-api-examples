#!/bin/bash
# ==============================================================================
# Script Name: 05.daemons_operations_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script performs operations on system daemons using the `/daemons/operations`
# endpoint. It demonstrates how to stop daemons both forcefully and gracefully,
# including setting a timeout for graceful shutdowns.
#
# Usage:
# ./05.daemons_operations_POST.sh
#
# Risk: disruptive - stops and starts daemons: every protocol on them goes down meanwhile
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The script uses basic authentication and POST requests with query parameters.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# Stop HTTP daemon forcefully
NAME="http"
OPERATION="stop"
GRACEFUL="false"

printf "Performing '${OPERATION}' on the '${NAME}' daemon...\n"
curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "POST" \
  "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/operations?operation=${OPERATION}&daemon=${NAME}&graceful=${GRACEFUL}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json"

# Gracefully stop SSH daemon with timeout
NAME="ssh"
OPERATION="stop"
GRACEFUL="true"
TIMEOUT="600" # 10 minutes

printf "Gracefully shutting down '${NAME}' with timeout '${TIMEOUT}'...\n"
curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "POST" \
  "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/operations?operation=${OPERATION}&daemon=${NAME}&graceful=${GRACEFUL}&timeout=${TIMEOUT}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json"
