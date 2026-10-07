#!/bin/bash
# ==============================================================================
# Script Name: 06.loginRestrictionPolicies_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script adds a rule to a login restriction policy using the
# `/loginRestrictionPolicies/{name}` endpoint with PATCH: allow or deny logins from an address,
# optionally only while an Expression Language condition is true.
#
# Usage:
# ./06.loginRestrictionPolicies_name_PATCH.sh [NAME [RULE_NAME [TYPE [ADDRESS [CONDITION]]]]]
#
#   NAME       the policy (default example_lrp)
#   RULE_NAME  the rule's name (default "example rule")
#   TYPE       ALLOW or DENY (default DENY)
#   ADDRESS    an IPv4 or IPv6 address, a network in CIDR notation, a host name, a domain such
#              as *.example.com, or * for any (default client.example.com, a name reserved for examples)
#   CONDITION  an Expression Language condition, for example ${currentSessions <= 3} (optional)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A policy that is not assigned to a business unit and is not the default has no
#   effect. Never make a policy the default (isDefault) to try it: that applies it to
#   every account that has no policy of its own.
# - NOT confirmed: that a policy assigned to a business unit changes who can log in. On
#   the lab these examples were checked against, a policy that denies every address,
#   assigned to a business unit, did not stop an account of that unit logging in over
#   FTP or the EndUser API. Check it on your own server before relying on it.
# - The condition holds ${...}, which is Expression Language, not a shell variable: single
#   quote it when you call this script.
# - Confirmed directly: rules are kept by name. Adding a rule whose name is already there
#   REPLACES it; the policy then still has one rule of that name. Two rules may share an
#   address.
# - Confirmed directly: /rules/- puts the new rule first, not last. The order does not matter:
#   rules of one type are one set.
# - Confirmed directly: the address is checked ("Unknown format for client address"), the
#   type is checked ("Valid type values are: ALLOW, DENY."), but the condition is not: an
#   expression that is not valid is accepted.
# - 08.loginRestrictionPolicies_name_PATCH_rule.sh enables, disables or removes a rule.
# - Requires `jq`, which URL-encodes the name and builds the patch.
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
TYPE="${3:-DENY}"
ADDRESS="${4:-client.example.com}"
CONDITION="$5"
if [ -z "${RULE_NAME// /}" ] || [[ "${RULE_NAME}" == *[/\;\']* ]]; then
    printf "RULE_NAME must not be blank, or contain / ; or ': %s\n" "${RULE_NAME}"
    exit 2
fi
if ! [[ "${TYPE}" =~ ^(ALLOW|DENY)$ ]]; then
    printf "TYPE is ALLOW or DENY, not %s.\n" "${TYPE}"
    exit 2
fi
if [ -z "${ADDRESS// /}" ]; then
    printf "ADDRESS must not be blank.\n"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

BODY=$(jq -cn --arg name "${RULE_NAME}" --arg type "${TYPE}" --arg address "${ADDRESS}" --arg condition "${CONDITION}" \
  '[{op: "add", path: "/rules/-", value: ({name: $name, isEnabled: true, type: $type, clientAddress: $address, description: "Added by 06.loginRestrictionPolicies_name_PATCH.sh"}
    + (if $condition != "" then {expression: $condition} else {} end))}]')

printf "Adding the rule %s to %s: %s %s%s...\n" "${RULE_NAME}" "${NAME}" "${TYPE}" "${ADDRESS}" "${CONDITION:+, only if ${CONDITION}}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
