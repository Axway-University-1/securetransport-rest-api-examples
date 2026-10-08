#!/bin/bash
# ==============================================================================
# Script Name: 12.certificates_requests_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads a certificate signing request, using the
# `/certificates/requests/{id}` endpoint.
#
# Usage:
# ./12.certificates_requests_id_GET.sh [REQUEST_ID]
#
#   REQUEST_ID  the request's id (default: the one request for
#               CN=example_csr,O=Example, which 09 creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is the request's JSON only, never the CSR;
#   asking for anything but JSON answers 406. Keep the CSR
#   09.certificates_requests_POST.sh writes.
# - Requires `jq`, which looks the id up.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates/requests"
REQUEST_ID="$1"
if [ "$#" -gt 1 ]; then
    printf "Usage: ./12.certificates_requests_id_GET.sh [REQUEST_ID]\n"
    exit 2
fi

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

if [ -z "${REQUEST_ID}" ]; then
    st_get -G "${MAIN_URL}" --data-urlencode "subject=CN=example_csr,O=Example"
    REQUEST_ID=$(printf '%s\n' "${RESPONSE}" | jq -r '.result // [] | if length == 1 then .[0].id else empty end')
    if [ -z "${REQUEST_ID}" ]; then
        printf "No single request for CN=example_csr,O=Example; give the request's id.\n"
        exit 1
    fi
fi

st_get "${MAIN_URL}/${REQUEST_ID}"
printf '%s' "${RESPONSE}"
printf "\n"
