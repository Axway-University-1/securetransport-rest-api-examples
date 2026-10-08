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
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The script uses basic authentication and filters JSON output using grep and cut.
# - Confirmed directly: /daemons/{name} answers only for ssh; any other name is 400 "Invalid value for parameter name,
#   expected (ssh)". The answer holds maxConnections, preferBouncyCastleProvider and banner (an empty text when none is set).
# - Every call is checked: a status other than 200 prints the status and the answer and ends the script with exit 1.
# - Exit codes: 0 when both answers are 200, 1 otherwise.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NAME="ssh"

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

# Query the SSH daemon
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/${NAME}"
printf '%s' "${RESPONSE}"

# Extract banner from response
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/${NAME}"
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
