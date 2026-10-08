#!/bin/bash
# ==============================================================================
# Script Name: 01.accessPolicies_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the database access policies using the `/accessPolicies`
# endpoint. They are the rules of the embedded PostgreSQL database's
# pg_hba.conf file: which connections, to which database, as which user, from
# which address, are allowed and how they authenticate. It demonstrates:
# - Listing every rule, in the order the database reads them
# - Asking for some fields only, with fields=
#
# Usage:
# ./01.accessPolicies_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Only for a server on the embedded PostgreSQL database.
# - Confirmed directly: the answer is a plain JSON array, not the
#   {"result": [...]} the API reference shows.
# - A rule's id is its line in the file. The database uses the first rule that
#   matches a connection, so the order matters.
# - Requires `jq`, which prints one rule per line.
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

printf "Every database access policy, in the order they are read:\n"
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accessPolicies"
printf '%s' "${RESPONSE}"

printf "\n\nThe same, one line each: id, connection type, database, user, address, method:\n"
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accessPolicies?fields=id,connectionType,database,user,address,authMethod"
printf '%s\n' "${RESPONSE}" | jq -r '.[] | "  \(.id)  \(.connectionType)  \(.database)  \(.user)  \(.address // "-")  \(.authMethod)"'
