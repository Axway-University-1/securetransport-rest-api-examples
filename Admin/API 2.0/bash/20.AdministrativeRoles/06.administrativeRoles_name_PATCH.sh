#!/bin/bash
# ==============================================================================
# Script Name: 06.administrativeRoles_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script adds a menu to an administrative role, using the
# `/administrativeRoles/{name}` endpoint with PATCH: a JSON Patch document that
# appends to the menus list.
#
# Usage:
# ./06.administrativeRoles_name_PATCH.sh [MENU]
#
#   MENU  the menu to add (default File Tracking)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The role is example_role, a limited role with the Change Password menu only.
#   02.administrativeRoles_POST.sh creates it.
# - "/menus/-" is the end of the list: add appends there. Confirmed directly:
#   the server does not keep the menus in order, so the new one may be
#   read back anywhere in the list.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which builds the patch.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrativeRoles"
ROLE="example_role"
MENU="${1:-File Tracking}"

BODY=$(jq -n --arg menu "${MENU}" '[{op: "add", path: "/menus/-", value: $menu}]')

printf "Adding the menu %s to %s...\n" "${MENU}" "${ROLE}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ROLE}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
