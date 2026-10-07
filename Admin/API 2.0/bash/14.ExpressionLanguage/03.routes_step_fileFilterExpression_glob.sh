#!/bin/bash
# ==============================================================================
# Script Name: 03.routes_step_fileFilterExpression_glob.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates a route step's fileFilterExpression using GLOB
# syntax - the simpler of the two pattern languages a step can filter files
# with (the other is REGEXP, see 04.routes_step_fileFilterExpression_regexp.sh
# in this folder). It creates one throwaway route per glob pattern from the
# EL documentation's "Pluggable transfer sites, Download pattern examples"
# table, each on a single EncodingConversion step:
#
#   *.xml       any file ending in .xml
#   foo.??      "foo." followed by exactly two characters
#   *.[0-9]     any file with a single digit extension
#   *.[!0-9]    any file with a single non-digit-character extension
#
# APIs used - /myself ( ST login and logout )
#             /routes ( POST, GET, DELETE )
#
# Usage:
# ./03.routes_step_fileFilterExpression_glob.sh
#
# Risk: write
#
# Notes:
# - Confirmed directly against a real server: fileFilterExpressionType only
#   accepts GLOB, REGEXP or TEXT_FILES - not "REGEX", which would be a
#   reasonable but wrong guess.
# - fileFilterExpression is a plain glob/regex string, not wrapped in
#   ${...} - it is evaluated by the file filter itself, not by the EL engine,
#   so none of the backslash-doubling rules that apply inside an EL string
#   literal apply here. See the gotchas skill for the confirmed distinction.
# ==============================================================================

SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"

create_route() {
    local suffix="$1"
    local pattern="$2"
    local name="ZZTEST_EL_glob_${suffix}"

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
        \"fileFilterExpressionType\": \"GLOB\",
        \"inputCharset\": \"UTF-8\",
        \"outputCharset\": \"UTF-8\",
        \"actionOnStepFailure\": \"PROCEED\"
      }]
    }"
}

create_route "anyXml"        '*.xml'
create_route "fooDotTwoAny"  'foo.??'
create_route "singleDigit"   '*.[0-9]'
create_route "notDigit"      '*.[!0-9]'

printf "\n\nReading all four back, and cleaning each up...\n"
for SUFFIX in anyXml fooDotTwoAny singleDigit notDigit; do
    NAME="ZZTEST_EL_glob_${SUFFIX}"
    printf "\n%s:\n" "${NAME}"
    curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=name,steps.fileFilterExpression,steps.fileFilterExpressionType" -H "accept: application/json" -H "${REFERER_HEADER}"

    ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')
    if [ -n "${ID}" ]; then
        curl -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ID}" -H "accept: application/json" -H "${REFERER_HEADER}"
        printf "\ndeleted %s (%s)\n" "${NAME}" "${ID}"
    fi
done
