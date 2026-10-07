#!/bin/bash
# ==============================================================================
# Script Name: 05.businessUnits_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a business unit, using the `/businessUnits/{name}`
# endpoint with PUT: it reads the unit, changes whether the accounts in it may
# change their home folders (homeFolderModifyingAllowed), and sends the whole
# unit back.
#
# Usage:
# ./05.businessUnits_name_PUT.sh NAME [VALUE]
#
#   NAME   the business unit
#   VALUE  the new homeFolderModifyingAllowed, true or false (default true)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the value before, to put it back with.
# - metadata, the read-only links, is left out of what is sent.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which URL-encodes the name and edits the unit.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/businessUnits"
NAME="$1"
[ -n "${NAME}" ] || { printf "Usage: ./05.businessUnits_name_PUT.sh NAME [VALUE]\n"; exit 2; }
VALUE="${2:-true}"
[[ "${VALUE}" =~ ^(true|false)$ ]] || { printf "VALUE is true or false, not %s.\n" "${VALUE}"; exit 2; }
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

BU_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${BU_JSON}" | jq -e '.name' >/dev/null 2>&1; then
    printf "There is no business unit %s.\n" "${NAME}"
    exit 1
fi
printf "homeFolderModifyingAllowed of %s is now %s.\n" "${NAME}" "$(printf '%s' "${BU_JSON}" | jq -r '.homeFolderModifyingAllowed')"
BODY=$(printf '%s' "${BU_JSON}" | jq -c --argjson value "${VALUE}" '.homeFolderModifyingAllowed = $value | del(.metadata)')

printf "Setting it to %s...\n" "${VALUE}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
