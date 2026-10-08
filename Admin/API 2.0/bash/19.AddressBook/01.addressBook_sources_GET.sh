#!/bin/bash
# ==============================================================================
# Script Name: 01.addressBook_sources_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the address book sources using the `/addressBook/sources`
# endpoint: where the end users' address book finds the people they share
# with - the local accounts, an LDAP directory, or a custom source. It
# demonstrates:
# - Listing every source
# - Filtering by type and by whether a source is enabled
# - Asking for some fields only, with fields=
#
# Usage:
# ./01.addressBook_sources_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - type is LOCAL, LDAP or CUSTOM. name and parentGroup filter too.
# - A server comes with its sources; the API has no POST or DELETE for them,
#   only reading and changing (see 04 and 05 in this folder).
# - Requires `jq`, which prints one source per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/addressBook/sources"

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

printf "Every address book source:\n"
st_get "${MAIN_URL}"
printf '%s' "${RESPONSE}"

printf "\n\nThe LDAP sources only:\n"
st_get "${MAIN_URL}?type=LDAP"
printf '%s' "${RESPONSE}"

printf "\n\nThe enabled ones, one line each: id, type, name, group:\n"
st_get "${MAIN_URL}?enabled=true&fields=id,type,name,parentGroup"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  \(.id)  \(.type)  \(.name)  \(.parentGroup)"'
