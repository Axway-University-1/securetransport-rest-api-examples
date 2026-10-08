#!/bin/bash
# ==============================================================================
# Script Name: 09.servers_name_GET.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves information about a specific server using the `/servers/{name}` endpoint.
# It demonstrates:
# - A full GET request for a server by name
# - A filtered GET request using the `fields` parameter (requires `protocol`)
#
# Usage:
# ./09.servers_name_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The `fields` parameter must be used in combination with `protocol`.
# - Confirmed directly: a server that does not exist is a 404 with an HTML page ("HTTP Status 404 - Not Found"), not JSON;
#   08.servers_name_HEAD.sh gets a bodiless 400 for the same name. The script prints the status and that page and exits 1.
# - Exit codes: 0 when both answers are 200, 1 otherwise.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

SERVER_NAME="SSH_TEST_SERVER_1"

# st_get CURL_ARGUMENTS...: a GET of the URL given (with any curl options, such as -G --data-urlencode ...). The answer
# is left in RESPONSE. A status other than 200 ends the script with exit 1, after printing the status and the answer.
st_get() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "$@" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}

# Full server details
printf "\nGetting %s...\n" "${SERVER_NAME}"
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${SERVER_NAME}"
printf '%s' "${RESPONSE}"

# Filtered fields (requires protocol)
printf "\nGetting %s with applied fields...\n" "${SERVER_NAME}"
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${SERVER_NAME}?fields=isActive,port&protocol=ssh"
printf '%s' "${RESPONSE}"
