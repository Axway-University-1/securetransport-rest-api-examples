#!/bin/bash
# ==============================================================================
# Script Name: 03.loginRestrictionPolicies_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a login restriction policy exists using the
# `/loginRestrictionPolicies/{name}` endpoint with HEAD: 200 when it does, 404 when not.
#
# Usage:
# ./03.loginRestrictionPolicies_name_HEAD.sh [NAME]
#
#   NAME  the policy (default example_lrp)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The name goes into the path URL-encoded once, with jq's @uri.
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

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The login restriction policy %s exists.\n" "${NAME}"
else
    printf "The login restriction policy %s does not exist (HTTP %s).\n" "${NAME}" "${HTTP_CODE}"
    exit 1
fi
