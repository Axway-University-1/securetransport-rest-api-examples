#!/bin/bash
# ==============================================================================
# Script Name: 01.administrators_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the administrators using the `/administrators` endpoint.
# It demonstrates:
# - Listing them, a page at a time
# - Filtering: the administrators that hold a role, the locked ones
# - Asking for some fields only, with fields=
#
# Usage:
# ./01.administrators_GET.sh [ROLE]
#
#   ROLE  the role to list the administrators of (default Master Administrator)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Many more filters exist: parent, isLimited, localAuthentication,
#   dualAuthentication, the password and login times, and the API keys' dates
#   and permissions. See the API reference.
# - Requires `jq`, which prints one administrator per line.
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
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ROLE="${1:-Master Administrator}"
if [ "$#" -gt 1 ]; then
    printf "Usage: ./01.administrators_GET.sh [ROLE]\n"
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

printf "The first 5 administrators, login name and role:\n"
st_get "${MAIN_URL}?limit=5&offset=0&fields=loginName,roleName"
printf '%s' "${RESPONSE}"

printf "\n\nThe ones that hold %s:\n" "${ROLE}"
st_get -G "${MAIN_URL}" --data-urlencode "roleName=${ROLE}" --data-urlencode "fields=loginName,parent,locked"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  \(.loginName)  created by \(.parent // "-")\(if .locked then "  LOCKED" else "" end)"'

printf "\nThe locked ones:\n"
st_get "${MAIN_URL}?locked=true&fields=loginName"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  " + .loginName'
