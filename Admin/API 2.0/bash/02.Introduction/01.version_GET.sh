#!/bin/bash
# ==============================================================================
# Script Name: 01.version_GET.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script performs a basic authentication request to retrieve the current
# product version from the API. It uses username and password credentials and
# sends a GET request to the `/version` endpoint.
#
# Usage:
# ./01.version_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This script uses basic authentication and will be updated to token-based
#   authentication in future iterations.
# ==============================================================================
# Load environment variables
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# Perform GET request to retrieve product version
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/version" \
  -H "accept: application/json" -H "${REFERER_HEADER}"

# End of script