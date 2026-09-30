#!/bin/bash
# ==============================================================================
# Script Name: 01.daemons_GET.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script queries the `/daemons` endpoint to retrieve system daemon statuses.
# It demonstrates how to extract specific fields from the response, such as
# `sshStatus`, using both full and filtered API calls.
#
# Usage:
# ./01.daemons_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The script uses basic authentication and filters JSON output using grep.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# Full response
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons" -H "accept: application/json" -H "${REFERER_HEADER}"

# Store full response in a variable
RESPONSE=$(curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons" -H "accept: application/json" -H "${REFERER_HEADER}")

# Extract sshStatus
echo "${RESPONSE}" | grep "sshStatus"

# Filtered response using 'fields' parameter
RESPONSE=$(curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons?fields=sshStatus" -H "accept: application/json" -H "${REFERER_HEADER}")
echo "${RESPONSE}"
