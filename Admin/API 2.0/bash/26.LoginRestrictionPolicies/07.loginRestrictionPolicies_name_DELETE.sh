#!/bin/bash
# ==============================================================================
# Script Name: 07.loginRestrictionPolicies_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a login restriction policy using the `/loginRestrictionPolicies/{name}`
# endpoint.
#
# Usage:
# ./07.loginRestrictionPolicies_name_DELETE.sh [NAME]
#
#   NAME  the policy (default example_lrp)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Only delete a policy you added: the business units it was assigned to lose its rules.
# - A name that does not exist answers 404.
# - Requires `jq`, which URL-encodes the name.
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

printf "Deleting the login restriction policy %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
