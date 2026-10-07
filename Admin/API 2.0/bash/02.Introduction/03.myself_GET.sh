#!/bin/bash
# ==============================================================================
# Script Name: 03.myself_GET.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script queries the API to retrieve information about the current user.
# It performs two GET requests:
#   1. To fetch full user details.
#   2. To extract the last password change time from the response.
#
# Usage:
# ./03.myself_GET.sh
#
# Risk: read
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

# Query the API to get full user information
printf "\n\nQuerying the API to get information about the current user...\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}"

# Query again and filter for last password change time
printf "\n\nQuerying the API again and filtering the response to find the last password change time...\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}" | grep "lastPasswordChangeTime"
