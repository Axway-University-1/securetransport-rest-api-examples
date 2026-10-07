#!/bin/bash
# ==============================================================================
# Script Name: 03.administrativeRoles_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether an administrative role exists, using the
# `/administrativeRoles/{name}` endpoint with HEAD: 200 when it does, 404 when
# it does not.
#
# Usage:
# ./03.administrativeRoles_name_HEAD.sh [ROLE]
#
#   ROLE  the role's name (default example_role)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A role name with spaces is URL-encoded in the path, as here.
# - Requires `jq`, which URL-encodes the name.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrativeRoles"
ROLE="${1:-example_role}"
ENCODED=$(jq -rn --arg role "${ROLE}" '$role | @uri')

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The role %s exists.\n" "${ROLE}"
else
    printf "The role %s does not exist (HTTP %s).\n" "${ROLE}" "${HTTP_CODE}"
    exit 1
fi
