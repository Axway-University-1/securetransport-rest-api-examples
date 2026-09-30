#!/bin/bash
# ==============================================================================
# Script Name: 02.routes_condition_EL.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates using an Expression Language (EL) condition on a
# route itself, rather than the built-in ALWAYS / MATCH_ALL / MATCH_FIRST
# condition types. It creates three throwaway routes, each conditionType=EL
# with a different worked expression from the EL documentation:
#
#   1. ${account.disabled != '0'}          - a relational comparison (conditional)
#   2. ${!empty account.email}             - the empty operator (conditional)
#   3. ${transfer.transferredBytes ge 20}  - a numeric comparison (arithmetic)
#
# APIs used - /myself ( ST login and logout )
#             /routes ( POST, GET, DELETE )
#
# Usage:
# ./02.routes_condition_EL.sh
#
# Notes:
# - Confirmed directly against a real server: conditionType accepts
#   MATCH_ALL, MATCH_FIRST, ALWAYS or EL. When it is EL, the expression text
#   goes in a field simply named "condition" - not "elCondition" or
#   "expression", which would be reasonable guesses but are wrong.
# - This is the route-level condition (does the whole route run at all), a
#   different field from a route *step's* own conditionType/condition, which
#   works the same way - see 03 and 04 in this folder for that, combined with
#   a file filter.
# - These routes are never attached to an account and never actually process
#   a file, so the condition is never evaluated for real here - this shows
#   the field is accepted and stored correctly, not what it evaluates to.
# - The JSON bodies below are single quoted, unlike most scripts in this
#   repository: nothing in them needs the shell to expand a variable, and
#   single quotes mean the EL syntax's own dollar-brace can be written
#   exactly as documented, with no backslash escaping needed at all.
# ==============================================================================

SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"

printf "\nCreating ZZTEST_EL_route_disabled with condition: \${account.disabled != '0'}\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d '{"name":"ZZTEST_EL_route_disabled","type":"SIMPLE","conditionType":"EL","condition":"${account.disabled != '"'"'0'"'"'}"}'

printf "\nCreating ZZTEST_EL_route_hasEmail with condition: \${!empty account.email}\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d '{"name":"ZZTEST_EL_route_hasEmail","type":"SIMPLE","conditionType":"EL","condition":"${!empty account.email}"}'

printf "\nCreating ZZTEST_EL_route_bytesGE20 with condition: \${transfer.transferredBytes ge 20}\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d '{"name":"ZZTEST_EL_route_bytesGE20","type":"SIMPLE","conditionType":"EL","condition":"${transfer.transferredBytes ge 20}"}'

printf "\nReading all three back...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=ZZTEST_EL_route_disabled&fields=name,condition,conditionType" -H "accept: application/json" -H "${REFERER_HEADER}"
printf "\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=ZZTEST_EL_route_hasEmail&fields=name,condition,conditionType" -H "accept: application/json" -H "${REFERER_HEADER}"
printf "\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=ZZTEST_EL_route_bytesGE20&fields=name,condition,conditionType" -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nCleaning up all three throwaway routes...\n"
for NAME in ZZTEST_EL_route_disabled ZZTEST_EL_route_hasEmail ZZTEST_EL_route_bytesGE20; do
    ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')
    if [ -n "${ID}" ]; then
        curl -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ID}" -H "accept: application/json" -H "${REFERER_HEADER}"
        printf "\ndeleted %s (%s)\n" "${NAME}" "${ID}"
    fi
done
