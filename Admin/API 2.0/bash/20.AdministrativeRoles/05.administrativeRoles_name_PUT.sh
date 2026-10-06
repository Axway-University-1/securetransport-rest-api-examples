#!/bin/bash
# ==============================================================================
# Script Name: 05.administrativeRoles_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces an administrative role, using the
# `/administrativeRoles/{name}` endpoint with PUT: it reads the role, sets its
# menus, and sends the whole role back.
#
# Usage:
# ./05.administrativeRoles_name_PUT.sh [MENU...]
#
#   MENU  the menus the role opens, each one argument (default: Change Password
#         and Audit Log)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The role is example_role, a limited role with the Change Password menu only.
#   02.administrativeRoles_POST.sh creates it.
# - PUT replaces the whole list; 06.administrativeRoles_name_PATCH.sh adds one
#   menu to it instead.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which edits the role.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrativeRoles"
ROLE="example_role"
if [ "$#" -eq 0 ]; then
    set -- "Change Password" "Audit Log"
fi

ROLE_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ROLE}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${ROLE_JSON}" | jq -e '.roleName' >/dev/null 2>&1; then
    printf "There is no role %s. Run 02.administrativeRoles_POST.sh first.\n" "${ROLE}"
    exit 1
fi

# The whole role, without the read-only links, with the new menus
BODY=$(printf '%s' "${ROLE_JSON}" | jq -c '.menus = $ARGS.positional | del(.metadata)' --args "$@")

printf "Setting the menus of %s to: %s\n" "${ROLE}" "$(printf '%s' "${BODY}" | jq -r '.menus | join(", ")')"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${ROLE}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
