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
if [ -n "${TYPE}" ] && ! [[ "${TYPE}" =~ ^(ALLOW_THEN_DENY|DENY_THEN_ALLOW)$ ]]; then
    printf "TYPE is ALLOW_THEN_DENY or DENY_THEN_ALLOW, not %s.\n" "${TYPE}"
    exit 2
fi
LINE='"  \(.name)  \(.type)  \(.rules | length) rule(s)  \(if .isDefault then "default  " else "" end)business units: \((.businessUnits // []) | if length == 0 then "-" else join(", ") end)"'
FIELDS="name,type,isDefault,rules,businessUnit"

printf "Login restriction policies: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=1&fields=name" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.resultSet.totalCount'

printf "\nThe policies named %s: name, type, rules, business units:\n" "${PATTERN}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${PATTERN}" --data-urlencode "fields=${FIELDS}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"

if [ -n "${TYPE}" ]; then
    printf "\nOnly the ones of type %s:\n" "${TYPE}"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "type=${TYPE}" --data-urlencode "fields=${FIELDS}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"
fi

printf "\nThe default policy, which applies to every account that has none of its own:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "isDefault=true" --data-urlencode "fields=${FIELDS}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"
