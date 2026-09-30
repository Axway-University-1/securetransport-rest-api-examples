#!/bin/bash
# ==============================================================================
# Script Name: 02.version_GET.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script performs a basic authentication request to retrieve the current
# product version from the API. It stores the full response in a variable and
# filters specific fields such as version, server type, and operating system.
#
# Usage:
# ./02.version_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This script demonstrates how to parse and filter JSON responses using grep.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# Store full response in a variable
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/version" -H "accept: application/json" -H "${REFERER_HEADER}")

# Uncomment to see full response
# echo "${RESPONSE}"

# Extract version
printf "grep for the version...\n"
echo "${RESPONSE}" | grep "version"

# Filter specific SPI version
printf "grep for version.*5.5...\n"
echo "${RESPONSE}" | grep "version.*5.5"

# Extract server type
printf "grep for serverType...\n"
echo "${RESPONSE}" | grep "serverType"

# Extract operating system
printf "grep for os...\n"
echo "${RESPONSE}" | grep "os"
