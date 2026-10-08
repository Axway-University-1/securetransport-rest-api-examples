#!/bin/bash
# ==============================================================================
# Script Name: 06.routes_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves routes using the `/routes` endpoint.
# It demonstrates:
# - A GET request for the composite routes, kept to one account and printed as
#   one line per route, with the template and subscriptions it is linked to
# - A GET request for one route by its id, printing the type of each step
#
# Usage:
# ./06.routes_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This example uses the account "john" and the simple route
#   SimpleRoute_Compress, which 03.routes_POST_simple_compress.sh creates.
# - Requires `jq`, which prints the short listings.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200 (also when there is no such simple route: that is said and is not an error), 1 otherwise.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"

ACCOUNT="john"
SIMPLE_ROUTE_NAME="SimpleRoute_Compress"

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

printf "The composite routes of '%s': id, name, template, subscriptions...\n" "${ACCOUNT}"
st_get "${MAIN_URL}/routes?type=COMPOSITE"
printf '%s\n' "${RESPONSE}" | jq -r --arg account "${ACCOUNT}" \
    '(.result // [])[] | select(.account == $account)
     | "\(.id)  \(.name)  template=\(.routeTemplate)  subscriptions=\((.subscriptions // []) | join(","))"'

printf "\nThe steps of the simple route '%s'...\n" "${SIMPLE_ROUTE_NAME}"
st_get "${MAIN_URL}/routes?fields=id&name=${SIMPLE_ROUTE_NAME}"
SIMPLE_ROUTE_ID=$(printf '%s\n' "${RESPONSE}" | jq -r '.result[0].id // empty')

if [ -z "${SIMPLE_ROUTE_ID}" ]; then
    printf "There is no route '%s'.\n" "${SIMPLE_ROUTE_NAME}"
    exit 0
fi

st_get "${MAIN_URL}/routes/${SIMPLE_ROUTE_ID}"
printf '%s\n' "${RESPONSE}" | jq -r '(.steps // [])[] | "  \(.type)  \(.status)"'
