#!/bin/bash
# ==============================================================================
# Script Name: 06.businessUnits_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes one property of a business unit, using the
# `/businessUnits/{name}` endpoint with PATCH: a JSON Patch document that sets
# whether the accounts in it may collaborate on shared folders
# (sharedFoldersCollaborationAllowed). Unlike PUT
# (05.businessUnits_name_PUT.sh), it sends only what changes.
#
# Usage:
# ./06.businessUnits_name_PATCH.sh NAME [VALUE]
#
#   NAME   the business unit
#   VALUE  the new sharedFoldersCollaborationAllowed, true or false (default
#          true)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the value before, to put it back with. A new unit has null: the
#   server's default applies.
# - Confirmed directly: replace works on a property that is null; a success
#   answers 204, with no body.
# - Requires `jq`, which URL-encodes the name and builds the patch.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/businessUnits"
NAME="$1"
[ -n "${NAME}" ] || { printf "Usage: ./06.businessUnits_name_PATCH.sh NAME [VALUE]\n"; exit 2; }
VALUE="${2:-true}"
[[ "${VALUE}" =~ ^(true|false)$ ]] || { printf "VALUE is true or false, not %s.\n" "${VALUE}"; exit 2; }
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

BEFORE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}?fields=sharedFoldersCollaborationAllowed" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.sharedFoldersCollaborationAllowed')
printf "sharedFoldersCollaborationAllowed of %s is now %s.\n" "${NAME}" "${BEFORE}"
BODY=$(jq -n --argjson value "${VALUE}" '[{op: "replace", path: "/sharedFoldersCollaborationAllowed", value: $value}]')

printf "Setting it to %s...\n" "${VALUE}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
