#!/bin/bash
# ==============================================================================
# Script Name: 04.loginRestrictionPolicies_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one login restriction policy using the `/loginRestrictionPolicies/{name}`
# endpoint: its type, its rules, and the business units it is assigned to.
#
# Usage:
# ./04.loginRestrictionPolicies_name_GET.sh [NAME]
#
#   NAME  the policy (default example_lrp)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The name goes into the path URL-encoded once, with jq's @uri.
# - A rule has an ALLOW or DENY type, a client address (an IP address, a network in CIDR
#   notation, a host or domain name, or * for any), an optional Expression Language
#   condition that must also be true, and can be disabled. Rules of one type are one set;
#   the policy's type says which set is evaluated first.
# - Confirmed directly: the rules come back newest first, and keep their ids across a PUT: a
#   rule is known by its name.
# - Requires `jq`, which URL-encodes the name and prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies"
NAME="${1:-example_lrp}"
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read %s (HTTP %s): " "${NAME}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '
  "  \(.name): \(.type), \(if .isDefault then "the default policy" else "not the default" end)",
  "  business units: \((.businessUnits // []) | if length == 0 then "none" else join(", ") end)",
  "  \(.rules | length) rule(s): name, type, address, enabled, condition:",
  (.rules[] | "    \(.name)  \(.type)  \(.clientAddress)  \(if .isEnabled then "enabled" else "disabled" end)  \(if (.expression // "") == "" then "-" else .expression end)")'
