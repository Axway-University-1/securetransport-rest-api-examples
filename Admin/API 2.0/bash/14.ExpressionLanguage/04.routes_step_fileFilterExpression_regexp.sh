#!/bin/bash
# ==============================================================================
# Script Name: 04.routes_step_fileFilterExpression_regexp.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates a route step's fileFilterExpression using REGEXP
# syntax - a plain (Java) regular expression, not a glob and not an EL
# expression. Three patterns from the EL documentation:
#
#   .*\.(xml|txt)                    names ending in .xml or .csv (alternation)
#   (?i)data\.xml                    data.xml, case insensitive
#   ^(?!.*__TID\d{6}__[A-Za-z0-9]{16}).*$   everything except one specific
#                                     generated-name shape (negative lookahead) -
#                                     this exact pattern is used on a real
#                                     transfer site's download pattern field,
#                                     per the source document.
#
# APIs used - /myself ( ST login and logout )
#             /routes ( POST, GET, DELETE )
#
# Usage:
# ./04.routes_step_fileFilterExpression_regexp.sh
#
# Risk: write
#
# Notes:
# - Confirmed directly against a real server: fileFilterExpression with
#   fileFilterExpressionType=REGEXP is a raw regular expression string - it
#   is NOT wrapped in ${...}, so the EL-specific "double every backslash
#   inside a ${...} string literal" rule does not apply to it semantically.
# - That is a different thing from JSON's own requirement: a literal
#   backslash inside ANY hand-written JSON string value - EL-wrapped or not -
#   must be written as \\ in the JSON text itself, or the JSON is invalid.
#   Confirmed directly: sending a single \. in a curl -d body here gets
#   "Incorrect JSON format" back immediately, before the regex is ever looked
#   at. The patterns below are written with the backslash doubled in this
#   script's own source for exactly that reason - a JSON requirement, not an
#   EL one. See 05.routes_step_condition_matches_backslashDoubling.sh in this
#   folder for what happens when a pattern needs BOTH rules at once (an EL
#   regex match, not a raw REGEXP filter), and the gotchas skill for both.
# ==============================================================================

SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"

create_route() {
    local suffix="$1"
    local pattern="$2"
    local name="ZZTEST_EL_regexp_${suffix}"

    printf "\nCreating %s with fileFilterExpression: %s\n" "${name}" "${pattern}"
    curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${name}\",
      \"type\": \"SIMPLE\",
      \"conditionType\": \"ALWAYS\",
      \"steps\": [{
        \"type\": \"EncodingConversion\",
        \"status\": \"ENABLED\",
        \"conditionType\": \"ALWAYS\",
        \"usePrecedingStepFiles\": false,
        \"fileFilterExpression\": \"${pattern}\",
        \"fileFilterExpressionType\": \"REGEXP\",
        \"inputCharset\": \"UTF-8\",
        \"outputCharset\": \"UTF-8\",
        \"actionOnStepFailure\": \"PROCEED\"
      }]
    }"
}

create_route "xmlOrTxt"          '.*\\.(xml|txt)'
create_route "caseInsensitive"   '(?i)data\\.xml'
create_route "negativeLookahead" '^(?!.*__TID\\d{6}__[A-Za-z0-9]{16}).*$'

printf "\n\nReading all three back, and cleaning each up...\n"
for SUFFIX in xmlOrTxt caseInsensitive negativeLookahead; do
    NAME="ZZTEST_EL_regexp_${SUFFIX}"
    printf "\n%s:\n" "${NAME}"
    curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=name,steps.fileFilterExpression,steps.fileFilterExpressionType" -H "accept: application/json" -H "${REFERER_HEADER}"

    ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')
    if [ -n "${ID}" ]; then
        curl -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ID}" -H "accept: application/json" -H "${REFERER_HEADER}"
        printf "\ndeleted %s (%s)\n" "${NAME}" "${ID}"
    fi
done
