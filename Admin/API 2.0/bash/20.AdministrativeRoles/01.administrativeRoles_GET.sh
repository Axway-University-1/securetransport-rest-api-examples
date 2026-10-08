#!/bin/bash
# ==============================================================================
# Script Name: 01.administrativeRoles_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the administrative roles using the `/administrativeRoles`
# endpoint. A role is the set of Admin UI menus - and with them, API resources -
# an administrator may use. It demonstrates:
# - Listing the roles, a page at a time
# - Filtering: only the limited roles
# - Asking for some fields only, with fields=
#
# Usage:
# ./01.administrativeRoles_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - roleName, isLimited, isBounceAllowed and menus filter too.
# - Confirmed directly: fields=roleType is refused ("Field roleType does not
#   exist."), although a role read whole carries roleType.
# - Each role has a link to its members: the administrators that hold it.
# - Requires `jq`, which prints one role per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when both answers are 200, 1 otherwise.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrativeRoles"

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

printf "The first 5 roles:\n"
st_get "${MAIN_URL}?limit=5&offset=0"
printf '%s' "${RESPONSE}"

printf "\n\nThe limited roles, one line each: name, the menus they open:\n"
st_get "${MAIN_URL}?isLimited=true&fields=roleName,menus"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  \(.roleName): \(.menus | join(", "))"'
