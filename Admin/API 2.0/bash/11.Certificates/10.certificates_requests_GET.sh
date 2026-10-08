#!/bin/bash
# ==============================================================================
# Script Name: 10.certificates_requests_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the certificate signing requests waiting on the server,
# using the `/certificates/requests` endpoint.
#
# Usage:
# ./10.certificates_requests_GET.sh [USAGE]
#
#   USAGE  local or private (default: both); anything else is refused with exit 2, nothing sent
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: with a filter, resultSet.totalCount still counts every
#   request; returnCount, and the result, are the filtered ones.
# - Confirmed directly: keySize reads 0 and signAlgorithm null, whatever the
#   request was made with.
# - Requires `jq`, which prints one request per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Confirmed directly: the lab does not check the usage= filter of this endpoint, so a text that is neither local nor private
#   lists every request (200). The script refuses it first, because the same filter on /certificates answers a misleading
#   403 "Insufficient permissions to perform the operation" (see 01.certificates_GET.sh).
# - Exit codes: 0 when the answer is 200, 1 when it is not, 2 when an argument is wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates/requests"
USAGE="$1"
# USAGE is one of two fixed words, so it is safe to put in the URL as it is
if [ "$#" -gt 1 ] || { [ -n "${USAGE}" ] && [ "${USAGE}" != "local" ] && [ "${USAGE}" != "private" ]; }; then
    printf "Usage: ./10.certificates_requests_GET.sh [local|private]\n"
    exit 2
fi
QUERY="fields=id,subject,usage,account"
[ -n "${USAGE}" ] && QUERY="${QUERY}&usage=${USAGE}"

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

printf "The requests: id, subject, usage, account:\n"
st_get "${MAIN_URL}?${QUERY}"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  \(.id)  \(.subject)  \(.usage)  \(.account // "-")"'
