#!/bin/bash
# ==============================================================================
# Script Name: 01.icapServers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the ICAP servers using the `/icapServers` endpoint: the antivirus
# or data loss prevention servers SecureTransport sends transfers to, to be scanned.
# It demonstrates:
# - Counting them, and listing them with their type, address and whether enabled
# - Only the enabled ones, with serverEnabled=
# - One server by its name, with basicSettings.name=
# - Only the ones of one type, with basicSettings.type=
#
# Usage:
# ./01.icapServers_GET.sh [NAME [TYPE]]
#
#   NAME  list the server with exactly this name (optional)
#   TYPE  only the servers of this type: INCOMING, OUTGOING or BOTH (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - An ICAP server scans transfers only for the business units that list it in
#   enabledIcapServers (see 12.BusinessUnits), and only while it is enabled.
# - Confirmed directly: the answer is {resultSet, result}. basicSettings.name= and
#   basicSettings.url= are matched exactly: no * wildcard, and not without regard to
#   case. A type that does not exist answers 400 "Unknown name value ... for enum
#   class".
# - Requires `jq`, which prints one server per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when TYPE is not INCOMING, OUTGOING or BOTH, or there are more than two arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/icapServers"
NAME="$1"
TYPE="$2"
if [ "$#" -gt 2 ]; then
    printf "Usage: ./01.icapServers_GET.sh [NAME [TYPE]]\n"
    exit 2
fi
if [ -n "${TYPE}" ] && ! [[ "${TYPE}" =~ ^(INCOMING|OUTGOING|BOTH)$ ]]; then
    printf "TYPE is INCOMING, OUTGOING or BOTH, not %s.\n" "${TYPE}"
    exit 2
fi
LINE='"  \(.basicSettings.name)  \(.basicSettings.type)  \(.basicSettings.url)  \(if .serverEnabled then "enabled" else "disabled" end)"'
FIELDS="serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url"

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

printf "ICAP servers: "
st_get "${MAIN_URL}?limit=1&fields=serverEnabled"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

printf "\nAll of them: name, type, address, enabled:\n"
st_get -G "${MAIN_URL}" --data-urlencode "fields=${FIELDS}"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"

printf "\nOnly the enabled ones:\n"
st_get -G "${MAIN_URL}" --data-urlencode "serverEnabled=true" --data-urlencode "fields=${FIELDS}"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"

if [ -n "${NAME}" ]; then
    printf "\nThe one named %s:\n" "${NAME}"
    st_get -G "${MAIN_URL}" --data-urlencode "basicSettings.name=${NAME}" --data-urlencode "fields=${FIELDS}"
    printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"
fi

if [ -n "${TYPE}" ]; then
    printf "\nOnly the ones of type %s:\n" "${TYPE}"
    st_get -G "${MAIN_URL}" --data-urlencode "basicSettings.type=${TYPE}" --data-urlencode "fields=${FIELDS}"
    printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"
fi
