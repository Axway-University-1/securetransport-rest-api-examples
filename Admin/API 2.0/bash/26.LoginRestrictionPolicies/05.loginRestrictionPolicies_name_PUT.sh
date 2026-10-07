#!/bin/bash
# ==============================================================================
# Script Name: 05.loginRestrictionPolicies_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a login restriction policy using the `/loginRestrictionPolicies/{name}`
# endpoint with PUT: it reads the policy, changes its description, and sends the whole policy
# back, rules and business units included.
#
# Usage:
# ./05.loginRestrictionPolicies_name_PUT.sh [NAME [DESCRIPTION]]
#
#   NAME         the policy (default example_lrp)
#   DESCRIPTION  the new description (default "Replaced by 05.loginRestrictionPolicies_name_PUT.sh")
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the description before, to put back with.
# - Confirmed directly: a PUT replaces everything. A body with no rules and no business units
#   empties both; this script sends back what it read, so nothing is lost. The rules keep
#   their ids.
# - Confirmed directly: a PUT whose body has another name RENAMES the policy (the old name is
#   gone). This script sets the name back to NAME, so it cannot rename.
# - A name that does not exist answers 404. metadata is read back and dropped.
# - Requires `jq`, which URL-encodes the name and edits the policy.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies"
NAME="${1:-example_lrp}"
DESCRIPTION="${2:-Replaced by 05.loginRestrictionPolicies_name_PUT.sh}"
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

POLICY=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${POLICY}" | jq -e '.name' >/dev/null 2>&1; then
    printf "There is no login restriction policy %s.\n" "${NAME}"
    exit 1
fi
printf "The description of %s is now: %s\n" "${NAME}" "$(printf '%s' "${POLICY}" | jq -r '.description // ""')"
BODY=$(printf '%s' "${POLICY}" | jq -c --arg name "${NAME}" --arg description "${DESCRIPTION}" 'del(.metadata) | .name = $name | .description = $description')

printf "Setting it to: %s\n" "${DESCRIPTION}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
