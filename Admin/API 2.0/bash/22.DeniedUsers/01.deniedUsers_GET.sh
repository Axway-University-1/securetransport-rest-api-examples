#!/bin/bash
# ==============================================================================
# Script Name: 01.deniedUsers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the denied users using the `/deniedUsers` endpoint: the login
# names that may not log in to SecureTransport, permanently or for a time.
# It demonstrates:
# - Counting them
# - Searching by login name, with the * wildcard
# - Only the permanent ones, and only the temporary ones (isPermanent=)
# - Only the ones blocked since a date (blockedAt.from=)
#
# Usage:
# ./01.deniedUsers_GET.sh [PATTERN [SINCE]]
#
#   PATTERN  a login name, * matches anything (default *)
#   SINCE    only the ones blocked on or after this date, as yyyy-MM-dd (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is {resultSet, result}; each entry has
#   loginName, blockedAt, blockedUntil, blockedBy and note.
# - Confirmed directly: blockedUntil null means blocked for good. A temporary
#   entry stays in the list after it expires, until the server's blocked users
#   cleaner removes it, so isPermanent=false can show entries that no longer
#   block anyone.
# - Confirmed directly: loginName= is matched without regard to case, but an
#   entry's name is case sensitive: example_denied and EXAMPLE_DENIED can both
#   be in the list.
# - Confirmed directly: blockedAt and blockedUntil take .from and .to, as
#   yyyy-MM-dd, an RFC 2822 date or a timestamp in milliseconds.
# - Requires `jq`, which prints one entry per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when SINCE is not a date as yyyy-MM-dd, or there are more than two arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/deniedUsers"
PATTERN="${1:-*}"
SINCE="$2"
if [ "$#" -gt 2 ]; then
    printf "Usage: ./01.deniedUsers_GET.sh [PATTERN [SINCE]]\n"
    exit 2
fi
if [ -n "${SINCE}" ] && ! [[ "${SINCE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    printf "SINCE is a date as yyyy-MM-dd: %s\n" "${SINCE}"
    exit 2
fi

LINE='"  \(.loginName)  \(if .blockedUntil == null then "permanent" else "until " + .blockedUntil end)  by \(.blockedBy // "-")  \(.note // "")"'

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

printf "Denied users: "
st_get "${MAIN_URL}?limit=1&fields=loginName"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

printf "\nThe login names matching %s: name, until, by, note:\n" "${PATTERN}"
st_get -G "${MAIN_URL}" --data-urlencode "loginName=${PATTERN}"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"

printf "\nOnly the permanent ones:\n"
st_get -G "${MAIN_URL}" --data-urlencode "loginName=${PATTERN}" --data-urlencode "isPermanent=true"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"

printf "\nOnly the temporary ones:\n"
st_get -G "${MAIN_URL}" --data-urlencode "loginName=${PATTERN}" --data-urlencode "isPermanent=false"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"

if [ -n "${SINCE}" ]; then
    printf "\nBlocked on or after %s:\n" "${SINCE}"
    st_get -G "${MAIN_URL}" --data-urlencode "loginName=${PATTERN}" --data-urlencode "blockedAt.from=${SINCE}"
    printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"
fi
