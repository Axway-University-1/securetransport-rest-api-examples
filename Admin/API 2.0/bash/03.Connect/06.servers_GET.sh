#!/bin/bash
# ==============================================================================
# Script Name: 06.servers_GET.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script queries the `/servers` endpoint to retrieve server information.
# It demonstrates how to:
# - Get all servers
# - Filter by specific fields
# - Filter by protocol
# - Use common filters like serverName, isActive, isFipsEnabled
# - Use protocol-specific filters like isScpEnabled
#
# Usage:
# ./06.servers_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The script uses basic authentication and GET requests with query parameters.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials)
#   prints the status and the answer and ends the script with exit 1.
# - Exit codes: 0 when every answer is 200, 1 otherwise.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

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

# Get all servers
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers"
printf '%s' "${RESPONSE}"

# Get only serverName and isActive fields
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers?fields=id,serverName,isActive"
printf '%s' "${RESPONSE}"

# Filter by protocol: AS2
PROTOCOL="as2"
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers?protocol=${PROTOCOL}&fields=id,serverName,isActive"
printf '%s' "${RESPONSE}"

# Filter by common fields
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers?limit=1&offset=0&serverName=Ssh%20Default&isActive=true&isFipsEnabled=false"
printf '%s' "${RESPONSE}"

# Filter by protocol-specific field
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers?fields=isScpEnabled&protocol=ssh"
printf '%s' "${RESPONSE}"
