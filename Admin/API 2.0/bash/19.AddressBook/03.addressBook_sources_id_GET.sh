#!/bin/bash
# ==============================================================================
# Script Name: 03.addressBook_sources_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one address book source, using the
# `/addressBook/sources/{id}` endpoint: its type, group, whether it is enabled,
# and its custom properties - for LDAP, the domain and the page size.
#
# Usage:
# ./03.addressBook_sources_id_GET.sh [SOURCE]
#
#   SOURCE  the source's name (default LDAP). Its id is looked up by name.
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which reads the id.
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
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/addressBook/sources"

SOURCE="${1:-LDAP}"
if [ "$#" -gt 1 ]; then
    printf "Usage: ./03.addressBook_sources_id_GET.sh [SOURCE]\n"
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

st_get -G "${MAIN_URL}" --data-urlencode "name=${SOURCE}" --data-urlencode "fields=id"
SOURCE_ID=$(printf '%s\n' "${RESPONSE}" | jq -r '.result[0].id // empty')
if [ -z "${SOURCE_ID}" ]; then
    printf "There is no address book source named %s.\n" "${SOURCE}"
    exit 1
fi

printf "The source %s:\n" "${SOURCE}"
st_get "${MAIN_URL}/${SOURCE_ID}"
printf '%s' "${RESPONSE}"

printf "\n\nOnly its custom properties:\n"
st_get "${MAIN_URL}/${SOURCE_ID}?fields=customProperties"
printf '%s' "${RESPONSE}"
printf "\n"
