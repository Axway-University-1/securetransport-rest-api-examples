#!/bin/bash
# ==============================================================================
# Script Name: 01.loginRestrictionPolicies_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the login restriction policies using the `/loginRestrictionPolicies`
# endpoint: the rules that say from where, and under which conditions, a user may log in.
# It demonstrates:
# - Counting them, and listing them with their rules and business units
# - Searching by name, with the * wildcard
# - Only the ones of one type, with type=
# - The default policy, with isDefault=true
#
# Usage:
# ./01.loginRestrictionPolicies_GET.sh [PATTERN [TYPE]]
#
#   PATTERN  a policy name, * matches anything (default *)
#   TYPE     ALLOW_THEN_DENY or DENY_THEN_ALLOW: only the policies of this type (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is {resultSet, result}. name= takes the * wildcard and
#   is matched without regard to case, unlike most other resources.
# - Confirmed directly: the business units are the field businessUnits, but fields= must
#   ask for it as businessUnit (singular); fields=businessUnits answers 400. The rules are
#   rules.
# - Requires `jq`, which prints one policy per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when TYPE is not ALLOW_THEN_DENY or DENY_THEN_ALLOW, or there are more than two arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies"
PATTERN="${1:-*}"
TYPE="$2"
if [ "$#" -gt 2 ]; then
    printf "Usage: ./01.loginRestrictionPolicies_GET.sh [PATTERN [TYPE]]\n"
    exit 2
fi
if [ -n "${TYPE}" ] && ! [[ "${TYPE}" =~ ^(ALLOW_THEN_DENY|DENY_THEN_ALLOW)$ ]]; then
    printf "TYPE is ALLOW_THEN_DENY or DENY_THEN_ALLOW, not %s.\n" "${TYPE}"
    exit 2
fi
LINE='"  \(.name)  \(.type)  \(.rules | length) rule(s)  \(if .isDefault then "default  " else "" end)business units: \((.businessUnits // []) | if length == 0 then "-" else join(", ") end)"'
FIELDS="name,type,isDefault,rules,businessUnit"

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

printf "Login restriction policies: "
st_get "${MAIN_URL}?limit=1&fields=name"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

printf "\nThe policies named %s: name, type, rules, business units:\n" "${PATTERN}"
st_get -G "${MAIN_URL}" --data-urlencode "name=${PATTERN}" --data-urlencode "fields=${FIELDS}"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"

if [ -n "${TYPE}" ]; then
    printf "\nOnly the ones of type %s:\n" "${TYPE}"
    st_get -G "${MAIN_URL}" --data-urlencode "type=${TYPE}" --data-urlencode "fields=${FIELDS}"
    printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"
fi

printf "\nThe default policy, which applies to every account that has none of its own:\n"
st_get -G "${MAIN_URL}" --data-urlencode "isDefault=true" --data-urlencode "fields=${FIELDS}"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"
