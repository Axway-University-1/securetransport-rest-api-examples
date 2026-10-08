#!/bin/bash
# ==============================================================================
# Script Name: 01.logs_audit_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the audit log using the `/logs/audit` endpoint: who created, changed or
# deleted what on the server, when, and from which address. It demonstrates:
# - Counting the entries, and the ones of the last hours (duration=)
# - The entries for one type of object, and one object by its exact name
# - Only the entries of one kind of operation
#
# Usage:
# ./01.logs_audit_GET.sh [HOURS [OBJECT_TYPE [OBJECT_NAME [OPERATION]]]]
#
#   HOURS        how far back to look, in whole hours (default 24)
#   OBJECT_TYPE  for example BusinessUnit or Account (optional)
#   OBJECT_NAME  one object's exact name (optional)
#   OPERATION    CREATE, UPDATE, DELETE or CREATE_OR_UPDATE (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The audit log is the server's record of changes made through the Admin UI and this API.
#   Confirmed directly: it is newest first, the opposite of the server log.
# - Confirmed directly: objectType= and objectName= are matched exactly, with case: BusinessUnit
#   finds the units, businessunit and Business find none, and there is no * wildcard.
#   userName= is a case sensitive part of the name.
# - Confirmed directly: fromDate and endDate are RFC 2822 dates, for example Wed, 07 Oct 2026
#   00:00:00 +0300; 2026-10-07 answers 400. duration= takes hours and needs no date.
# - An operation that does not exist answers 400 "Unknown name value ... for enum class".
# - Requires `jq`, which prints one entry per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when HOURS or OPERATION is wrong, or there are more than four arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/audit"
HOURS="${1:-24}"
OBJECT_TYPE="$2"
OBJECT_NAME="$3"
OPERATION="$4"
if [ "$#" -gt 4 ]; then
    printf "Usage: ./01.logs_audit_GET.sh [HOURS [OBJECT_TYPE [OBJECT_NAME [OPERATION]]]]\n"
    exit 2
fi
[[ "${HOURS}" =~ ^[1-9][0-9]*$ ]] || { printf "HOURS must be a whole number of 1 or more: %s\n" "${HOURS}"; exit 2; }
if [ -n "${OPERATION}" ] && ! [[ "${OPERATION}" =~ ^(CREATE|UPDATE|DELETE|CREATE_OR_UPDATE)$ ]]; then
    printf "OPERATION is CREATE, UPDATE, DELETE or CREATE_OR_UPDATE, not %s.\n" "${OPERATION}"
    exit 2
fi
LINE='"  \(.dateModified)  \(.operationType)  \(.objectType) \(.objectName // "-")  by \(.userName // "-") from \(.remoteAddress // "-")"'
FIELDS="id,dateModified,operationType,objectType,objectName,userName,remoteAddress"

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

printf "Audit log entries: "
st_get "${MAIN_URL}?limit=1&fields=id"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

printf "\nThe last %s hour(s): " "${HOURS}"
st_get -G "${MAIN_URL}" --data-urlencode "duration=${HOURS}" --data-urlencode "limit=1" --data-urlencode "fields=id"
printf '%s\n' "${RESPONSE}" | jq -r '"\(.resultSet.totalCount) entries"'
printf "The latest 5, newest first:\n"
st_get -G "${MAIN_URL}" --data-urlencode "duration=${HOURS}" --data-urlencode "limit=5" --data-urlencode "fields=${FIELDS}"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"

FILTER=()
[ -n "${OBJECT_TYPE}" ] && FILTER+=(--data-urlencode "objectType=${OBJECT_TYPE}")
[ -n "${OBJECT_NAME}" ] && FILTER+=(--data-urlencode "objectName=${OBJECT_NAME}")
[ -n "${OPERATION}" ] && FILTER+=(--data-urlencode "operationType=${OPERATION}")
if [ "${#FILTER[@]}" -gt 0 ]; then
    printf "\nThe latest 10 entries for those filters:\n"
    st_get -G "${MAIN_URL}" "${FILTER[@]}" --data-urlencode "limit=10" --data-urlencode "fields=${FIELDS}"
    printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"
fi
