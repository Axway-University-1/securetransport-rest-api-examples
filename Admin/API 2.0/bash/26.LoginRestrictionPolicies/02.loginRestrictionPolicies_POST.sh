#!/bin/bash
# ==============================================================================
# Script Name: 02.loginRestrictionPolicies_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a login restriction policy using the `/loginRestrictionPolicies`
# endpoint: its name and type, with no rules yet and no business unit.
#
# Usage:
# ./02.loginRestrictionPolicies_POST.sh [NAME [TYPE [DESCRIPTION]]]
#
#   NAME         the policy's name (default example_lrp)
#   TYPE         ALLOW_THEN_DENY or DENY_THEN_ALLOW (default ALLOW_THEN_DENY): which set of
#                rules is evaluated first
#   DESCRIPTION  optional
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
# - Confirmed directly: type is required, though the reference marks only name and type as
#   an object; a body without it answers 400 "type must not be null". A name that exists
#   answers 409; one with / ; or ' answers 400.
# - The answer is 201 with the policy's address, which ends with its name, in Location.
# - 06.loginRestrictionPolicies_name_PATCH.sh adds a rule, 09.loginRestrictionPolicies_name_PATCH_businessUnit.sh
#   assigns it, 07.loginRestrictionPolicies_name_DELETE.sh removes it.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies"
NAME="${1:-example_lrp}"
TYPE="${2:-ALLOW_THEN_DENY}"
DESCRIPTION="$3"
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT
if [ -z "${NAME// /}" ] || [[ "${NAME}" == *[/\;\']* ]]; then
    printf "NAME must not be blank, or contain / ; or ': %s\n" "${NAME}"
    exit 2
fi
if ! [[ "${TYPE}" =~ ^(ALLOW_THEN_DENY|DENY_THEN_ALLOW)$ ]]; then
    printf "TYPE is ALLOW_THEN_DENY or DENY_THEN_ALLOW, not %s.\n" "${TYPE}"
    exit 2
fi

BODY=$(jq -cn --arg name "${NAME}" --arg type "${TYPE}" --arg description "${DESCRIPTION}" \
  '{name: $name, type: $type} + (if $description != "" then {description: $description} else {} end)')

printf "Creating the login restriction policy %s, %s...\n" "${NAME}" "${TYPE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -D "${HEADERS_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf "It is at %s\n" "$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r')"
