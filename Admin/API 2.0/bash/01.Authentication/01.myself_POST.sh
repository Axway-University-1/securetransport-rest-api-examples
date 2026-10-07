#!/bin/bash
# ==============================================================================
# Script Name: 01.myself_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script performs a basic authentication request to the API using a
# username and password. It retrieves user information from the `/myself` endpoint.
#
# Usage:
# ./01.myself_POST.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This script does not use a cookie jar, so authentication is required for each call.
# ==============================================================================
printf "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

printf "\n\nBasic authentication...\n"

curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}"
