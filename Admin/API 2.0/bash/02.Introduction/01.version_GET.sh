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
# - 02.version_GET.sh makes the very same call and then picks fields out of the answer with grep.
# - Confirmed directly: the answer is 200 with serverType, version, build, os, updateLevel and more. Refused credentials
#   answer 401 with the plain text "Authentication required.": the script prints the status and that text, and exits 1.
# - Exit codes: 0 when the answer is 200, 1 otherwise.
# ==============================================================================
# Load environment variables
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# Perform GET request to retrieve product version
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/version" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}"

# End of script