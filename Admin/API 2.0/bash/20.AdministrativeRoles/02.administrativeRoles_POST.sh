#!/bin/bash
# ==============================================================================
# Script Name: 02.administrativeRoles_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script creates an administrative role using the `/administrativeRoles`
# endpoint: a name, and the Admin UI menus the role opens.
#
# Usage:
# ./02.administrativeRoles_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The role is example_role, a limited role with the Change Password menu only.
# - A limited role (isLimited) can only manage what its own administrators
#   create. isBounceAllowed lets it restart the server.
# - menus are the Admin UI's own names: User Accounts, File Tracking, Audit
#   Log, Certificates and so on; the API reference lists them all.
# - 07.administrativeRoles_name_DELETE.sh removes it again.
# - Requires `jq`, which builds the request body.
# - Confirmed directly: a success is 201 with no body and the role's address in `Location`. A role that exists is 409 "Administrative role with the
#   same name already exist on the server." (nothing is changed), and a menu the server does not know 400 "List contains unsupported menu.".
# - Exit codes: 0 when the role was created (201), 1 when the server refuses.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrativeRoles"
ROLE="example_role"

BODY=$(jq -cn --arg role "${ROLE}" '{roleName: $role, isLimited: true, isBounceAllowed: false, menus: ["Change Password"]}')

printf "Creating the role %s...\n" "${ROLE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
