#!/bin/bash
# ==============================================================================
# Script Name: 06.routes_step_renameExpression.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates postTransformationActionRenameAsExpression - an EL
# expression that builds a new file name after a route step runs. Three
# worked examples from the EL documentation's predefined-functions appendix
# and file-name-examples table:
#
#   ${basename(transfer.target)}-${date('yyyyMMdd_HHmmss')}${extension(transfer.target)}
#       strips the extension, adds a timestamp, then re-adds the extension.
#       Note extension() includes the leading dot, so no extra '.' is needed.
#
#   ${basename(transfer.target)}-${random()}.${extension(transfer.target)}
#       appends a random ID instead of a timestamp. This one, from the EL
#       appendix's own example, writes an extra literal '.' before
#       ${extension(...)} - inconsistent with extension() already including
#       the dot (see the gotchas skill); kept here exactly as documented so
#       the inconsistency is visible, not silently corrected.
#
#   ${account.name}_${basename(transfer.target)}
#       prefixes the file name with the current account's name.
#
# APIs used - /myself ( ST login and logout )
#             /routes ( POST, GET, DELETE )
#
# Usage:
# ./06.routes_step_renameExpression.sh
#
# Risk: write
#
# Notes:
# - Confirmed directly against a real server: this field round trips exactly
#   as sent - no backslash-doubling is needed for any of the three examples,
#   since none of them use a regex.
# - What the expression actually renames a file to is not tested here - that
#   needs a live transfer with a real file, not something this repository's
#   integration checks set up. This proves the field accepts and stores the
#   expression correctly, not what it produces.
# ==============================================================================

SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"

create_route() {
    local suffix="$1"
    local rename_expr="$2"
    local name="ZZTEST_EL_rename_${suffix}"

    printf "\nCreating %s with postTransformationActionRenameAsExpression: %s\n" "${name}" "${rename_expr}"
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
        \"fileFilterExpression\": \"*\",
        \"fileFilterExpressionType\": \"GLOB\",
        \"inputCharset\": \"UTF-8\",
        \"outputCharset\": \"UTF-8\",
        \"postTransformationActionRenameAsExpression\": \"${rename_expr}\",
        \"actionOnStepFailure\": \"PROCEED\"
      }]
    }"
}

create_route "timestamped" '${basename(transfer.target)}-${date('"'"'yyyyMMdd_HHmmss'"'"')}${extension(transfer.target)}'
create_route "randomId"    '${basename(transfer.target)}-${random()}.${extension(transfer.target)}'
create_route "accountName" '${account.name}_${basename(transfer.target)}'

printf "\n\nReading all three back, and cleaning each up...\n"
for SUFFIX in timestamped randomId accountName; do
    NAME="ZZTEST_EL_rename_${SUFFIX}"
    printf "\n%s:\n" "${NAME}"
    curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=name,steps.postTransformationActionRenameAsExpression" -H "accept: application/json" -H "${REFERER_HEADER}"

    ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')
    if [ -n "${ID}" ]; then
        curl -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ID}" -H "accept: application/json" -H "${REFERER_HEADER}"
        printf "\ndeleted %s (%s)\n" "${NAME}" "${ID}"
    fi
done
