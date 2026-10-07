#!/bin/bash
# ==============================================================================
# Script Name: 05.routes_step_condition_matches_backslashDoubling.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script isolates the single most error-prone thing about writing an EL
# regex: two independent escaping layers stack on top of each other, and
# getting only one of them right still produces something that looks fine.
#
#   Layer 1 - Java regex: a literal dot needs one backslash:            \.
#   Layer 2 - the EL string literal that holds that regex, per the EL
#             documentation's own rule ("every backslash must be written
#             twice"): the regex text above, written inside ${...}, becomes: \\.
#             So the EL expression text a human reads is:
#                 ${transfer.target.matches('.*\\.txt')}
#   Layer 3 - JSON, once that whole EL expression is the value of a JSON
#             field: every backslash in the EL text is itself escaped again
#             for JSON. Two backslash characters become four in the JSON
#             source text:
#                 "condition": "${transfer.target.matches('.*\\\\.txt')}"
#
# This script creates two throwaway routes so the difference is visible
# side by side:
#
#   ZZTEST_EL_doubled  - four backslashes in this script's own source (the
#                        correct, fully-escaped form above)
#   ZZTEST_EL_single   - two backslashes in this script's own source, which
#                        is valid JSON and gets stored without complaint, but
#                        is missing the EL layer's own doubling. Per the EL
#                        documentation's own worked example ("Unescaped-dot
#                        form... looser because the unescaped dot matches any
#                        character"), this changes what the expression
#                        matches once it actually runs - it is not merely
#                        cosmetic.
#
# APIs used - /myself ( ST login and logout )
#             /routes ( POST, GET, DELETE )
#
# Usage:
# ./05.routes_step_condition_matches_backslashDoubling.sh
#
# Risk: write
#
# Notes:
# - Confirmed directly against a real server: a route with the four
#   backslash form stores a condition value containing exactly two backslash
#   characters (json-encoded back as \\\\ in a pretty-printed response,
#   which is JSON's own display convention for two real backslash
#   characters) - this script's GET step shows both stored values so the
#   difference is directly visible, not just asserted.
# - What each stored value actually MATCHES against a real file name at
#   transfer time is not tested here - that needs a live transfer, which is
#   a different kind of test than this repository's integration checks run.
#   See 04.routes_step_fileFilterExpression_regexp.sh's notes for the
#   related, but distinct, rule about a *raw* (non-EL) regex field.
# ==============================================================================

SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"

printf "\nCreating ZZTEST_EL_doubled - the correctly escaped form (4 backslashes in this script's source)...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d '{"name":"ZZTEST_EL_doubled","type":"SIMPLE","conditionType":"EL","condition":"${transfer.target.matches('"'"'.*\\\\.txt'"'"')}"}'

printf "\n\nCreating ZZTEST_EL_single - missing the EL layers own doubling (2 backslashes in this script's source)...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d '{"name":"ZZTEST_EL_single","type":"SIMPLE","conditionType":"EL","condition":"${transfer.target.matches('"'"'.*\\.txt'"'"')}"}'

printf "\n\nReading both back - compare the number of backslashes in each condition value:\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=ZZTEST_EL_doubled&fields=name,condition" -H "accept: application/json" -H "${REFERER_HEADER}"
printf "\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=ZZTEST_EL_single&fields=name,condition" -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nCleaning up both throwaway routes...\n"
for NAME in ZZTEST_EL_doubled ZZTEST_EL_single; do
    ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')
    if [ -n "${ID}" ]; then
        curl -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ID}" -H "accept: application/json" -H "${REFERER_HEADER}"
        printf "\ndeleted %s (%s)\n" "${NAME}" "${ID}"
    fi
done
