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
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The script uses basic authentication and filters JSON output using grep.
# - Confirmed directly: the answer is a flat object, {"ftpStatus": "Running", "httpStatus": "Running", "pesitStatus": ...,
#   "sshStatus": ..., "as2Status": "Not running"}, and fields=sshStatus keeps that one key.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty answer.
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

# Full response
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons"
printf '%s' "${RESPONSE}"

# Store full response in a variable
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons"

# Extract sshStatus
echo "${RESPONSE}" | grep "sshStatus"

# Filtered response using 'fields' parameter
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons?fields=sshStatus"
echo "${RESPONSE}"
