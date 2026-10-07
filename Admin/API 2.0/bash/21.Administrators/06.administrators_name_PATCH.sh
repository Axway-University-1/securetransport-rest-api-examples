#!/bin/bash
# ==============================================================================
# Script Name: 06.administrators_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script locks an administrator, using the `/administrators/{name}`
# endpoint with PATCH: a JSON Patch document that replaces locked. A locked
# administrator cannot log in.
#
# Usage:
# ./06.administrators_name_PATCH.sh [ADMIN]
#
#   ADMIN  the login name (default example_admin)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - 05.administrators_name_PUT.sh unlocks it again.
# - Confirmed directly: a success answers 204, with no body.
# - Never point it at the administrator you log in as.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="${1:-example_admin}"
if [ "${ADMIN}" = "${ST_USER}" ]; then
    printf "That is the administrator this script logs in as. Not locking it.\n"
    exit 2
fi

printf "Locking %s...\n" "${ADMIN}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ADMIN}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d '[{"op":"replace","path":"/locked","value":true}]')
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
