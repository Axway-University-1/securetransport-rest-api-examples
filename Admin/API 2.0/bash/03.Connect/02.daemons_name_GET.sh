#!/bin/bash
# ==============================================================================
# Script Name: 02.daemons_name_GET.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script queries the SSH daemon from the `/daemons/{name}` endpoint,
# extracts the banner from the response, checks if it's defined, and simulates
# a fake banner check.
#
# Usage:
# ./02.daemons_name_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The script uses basic authentication and filters JSON output using grep and cut.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NAME="ssh"

# Query the SSH daemon
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/${NAME}" -H "accept: application/json" -H "${REFERER_HEADER}"

# Extract banner from response
RESPONSE=$(curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/${NAME}" -H "accept: application/json" -H "${REFERER_HEADER}")
BANNER=$(echo "${RESPONSE}" | grep "banner" | cut -d '"' -f 4)

# Check if banner is defined
if [ -z "${BANNER}" ]; then
    echo "There is no banner defined."
else
    echo "There is a banner defined: '${BANNER}'."
fi
# Simulate a fake banner
echo "Setting the banner..."
FAKE_JSON='"banner": "This is a SecureTransport REST API test banner."'
BANNER=$(echo "${FAKE_JSON}" | grep "banner" | cut -d '"' -f 4)

# Check if fake banner is defined
if [ -z "${BANNER}" ]; then
    echo "There is no banner defined."
else
    echo "There is a banner defined: '${BANNER}'."
fi
