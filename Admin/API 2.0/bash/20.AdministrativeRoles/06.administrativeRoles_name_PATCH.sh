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
# - Confirmed directly: a success answers 204, with no body. A menu the server does not know is 400 "List contains unsupported menu." and a role
#   that does not exist 404 "No such administrative role."; the role is not changed by either.
# - Requires `jq`, which builds the patch.
# - Exit codes: 0 when the menu was added (204), 1 when the server refuses, 2 when the menu is empty (nothing is sent).
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
if [ -z "${MENU// /}" ] || [ "$#" -gt 1 ]; then
    printf "Usage: ./06.administrativeRoles_name_PATCH.sh [MENU]\n"
    exit 2
fi

BODY=$(jq -n --arg menu "${MENU}" '[{op: "add", path: "/menus/-", value: $menu}]')

printf "Adding the menu %s to %s...\n" "${MENU}" "${ROLE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ROLE}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
