#!/bin/bash
# ==============================================================================
# Script Name: 08.loginRestrictionPolicies_name_PATCH_rule.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script enables, disables or removes one rule of a login restriction policy using the
# `/loginRestrictionPolicies/{name}` endpoint with PATCH.
#
# Usage:
# ./08.loginRestrictionPolicies_name_PATCH_rule.sh [NAME [RULE_NAME [ACTION]]]
#
#   NAME       the policy (default example_lrp)
#   RULE_NAME  the rule (default "example rule")
#   ACTION     enable, disable or remove (default disable)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A rule is addressed by its position in the rules list, which changes as rules are added
#   (new ones go first) and removed. This script reads the policy and finds the position of
#   the rule by its name, so it cannot hit another rule.
# - A disabled rule stays in the policy and is not used until it is enabled again.
# - Requires `jq`, which URL-encodes the name, finds the rule and builds the patch.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies"
NAME="${1:-example_lrp}"
RULE_NAME="${2:-example rule}"
ACTION="${3:-disable}"
if ! [[ "${ACTION}" =~ ^(enable|disable|remove)$ ]]; then
    printf "ACTION is enable, disable or remove, not %s.\n" "${ACTION}"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

INDEX=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg rule "${RULE_NAME}" '(.rules // []) | map(.name) | index($rule) // empty' 2>/dev/null)
if [ -z "${INDEX}" ]; then
    printf "The policy %s has no rule named %s.\n" "${NAME}" "${RULE_NAME}"
    exit 1
fi
BODY=$(jq -cn --arg action "${ACTION}" --arg index "${INDEX}" \
  'if $action == "remove" then [{op: "remove", path: "/rules/\($index)"}]
   else [{op: "replace", path: "/rules/\($index)/isEnabled", value: ($action == "enable")}] end')

printf "%s the rule %s of %s (position %s)...\n" "${ACTION}" "${RULE_NAME}" "${NAME}" "${INDEX}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
