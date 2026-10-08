#!/bin/bash
# ==============================================================================
# Script Name: 03.configurations_options_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the Server Configuration Options using the
# `/configurations/options` endpoint. It demonstrates:
# - Counting them
# - Searching by name, with the * wildcard
# - The ones changed from their default (isModified=true)
# - Asking for some fields only, with fields=
#
# Usage:
# ./03.configurations_options_GET.sh [PATTERN]
#
#   PATTERN  an option name, * matches anything (default AddressBook*)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - values is always a list, even for an option with one value; defaultValues
#   is the value it has when nothing is set.
# - values= searches by value, also with *.
# - Requires `jq`, which prints one option per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there is more than one argument (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
PATTERN="${1:-AddressBook*}"
if [ "$#" -gt 1 ]; then
    printf "Usage: ./03.configurations_options_GET.sh [PATTERN]\n"
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

printf "Server Configuration Options: "
st_get "${MAIN_URL}/options?limit=1&fields=name"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

printf "\nThe options named %s: name = values (default):\n" "${PATTERN}"
st_get -G "${MAIN_URL}/options" --data-urlencode "name=${PATTERN}" --data-urlencode "fields=name,values,defaultValues"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  \(.name) = \(.values | join(", ")) (\(.defaultValues | join(", ")))"'

printf "\nThe first 10 options changed from their default:\n"
st_get "${MAIN_URL}/options?isModified=true&limit=10&fields=name,values"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  \(.name) = \(.values | join(", "))"'
