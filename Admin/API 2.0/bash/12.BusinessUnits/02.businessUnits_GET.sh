#!/bin/bash
# ==============================================================================
# Script Name: 02.businessUnits_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the business units using the `/businessUnits` endpoint.
# It demonstrates:
# - Listing them, a page at a time
# - Searching by name, with the * wildcard
# - The units nested under another one, with parent=
#
# Usage:
# ./02.businessUnits_GET.sh [PATTERN [PARENT]]
#
#   PATTERN  a name, * matches anything (default *)
#   PARENT   list the units nested under this one (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: baseFolder= is ignored, every value gives every unit.
# - Confirmed directly: parent is always null in an answer, even for a nested
#   unit; businessUnitHierarchy, parent/child, and
#   metadata.links.parentBusinessUnit are where the nesting shows. parent= as a
#   filter does work.
# - Requires `jq`, which prints one unit per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there are more than two arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/businessUnits"
PATTERN="${1:-*}"
PARENT="$2"
if [ "$#" -gt 2 ]; then
    printf "Usage: ./02.businessUnits_GET.sh [PATTERN [PARENT]]\n"
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

printf "The first 5 business units:\n"
st_get "${MAIN_URL}?limit=5&offset=0"
printf '%s' "${RESPONSE}"

printf "\n\nThe units named %s: hierarchy, base folder:\n" "${PATTERN}"
st_get -G "${MAIN_URL}" --data-urlencode "name=${PATTERN}" --data-urlencode "fields=businessUnitHierarchy,baseFolder"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  \(.businessUnitHierarchy)  \(.baseFolder)"'

if [ -n "${PARENT}" ]; then
    printf "\nThe units nested under %s:\n" "${PARENT}"
    st_get -G "${MAIN_URL}" --data-urlencode "parent=${PARENT}" --data-urlencode "fields=name"
    printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  " + .name'
fi
