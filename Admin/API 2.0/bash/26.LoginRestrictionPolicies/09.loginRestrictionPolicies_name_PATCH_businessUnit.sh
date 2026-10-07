#!/bin/bash
# ==============================================================================
# Script Name: 09.loginRestrictionPolicies_name_PATCH_businessUnit.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script assigns a login restriction policy to a business unit, or takes it away, using
# the `/loginRestrictionPolicies/{name}` endpoint with PATCH.
#
# Usage:
# ./09.loginRestrictionPolicies_name_PATCH_businessUnit.sh NAME BUSINESS_UNIT [add|remove]
#
#   NAME           the policy
#   BUSINESS_UNIT  the business unit
#   add|remove     assign it, or take it away (default add)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - NOT confirmed: that a policy assigned to a business unit changes who can log in. On
#   the lab these examples were checked against, a policy that denies every address,
#   assigned to a business unit, did not stop an account of that unit logging in over
#   FTP or the EndUser API. Check it on your own server before relying on it.
# - The unit is required: assigning a policy is meant to change what that unit's accounts can do.
# - Confirmed directly: assigning goes to /businessUnits/-; assigning a unit that is already
#   there changes nothing; a unit that does not exist answers 400 "Cannot find business unit".
#   Taking one away is by its position, which this script finds in the policy.
# - Confirmed directly: businessUnits?assignedToLoginRestrictionPolicies=, the filter the
#   server links to, filters nothing: every value lists every unit. Read the policy instead.
# - Requires `jq`, which URL-encodes the name and builds the patch.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies"
NAME="$1"
BUSINESS_UNIT="$2"
ACTION="${3:-add}"
if [ -z "${NAME}" ] || [ -z "${BUSINESS_UNIT}" ] || ! [[ "${ACTION}" =~ ^(add|remove)$ ]]; then
    printf "Usage: ./09.loginRestrictionPolicies_name_PATCH_businessUnit.sh NAME BUSINESS_UNIT [add|remove]\n"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

if [ "${ACTION}" = "add" ]; then
    BODY=$(jq -cn --arg unit "${BUSINESS_UNIT}" '[{op: "add", path: "/businessUnits/-", value: $unit}]')
else
    INDEX=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" \
      | jq -r --arg unit "${BUSINESS_UNIT}" '(.businessUnits // []) | index($unit) // empty' 2>/dev/null)
    if [ -z "${INDEX}" ]; then
        printf "The policy %s is not assigned to %s.\n" "${NAME}" "${BUSINESS_UNIT}"
        exit 1
    fi
    BODY=$(jq -cn --arg index "${INDEX}" '[{op: "remove", path: "/businessUnits/\($index)"}]')
fi

printf "%s the business unit %s, policy %s...\n" "${ACTION}" "${BUSINESS_UNIT}" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
