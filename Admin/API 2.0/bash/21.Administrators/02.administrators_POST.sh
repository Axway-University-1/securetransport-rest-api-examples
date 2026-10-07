#!/bin/bash
# ==============================================================================
# Script Name: 02.administrators_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script creates an administrator using the `/administrators` endpoint: a
# login name, a role, and a password.
#
# Usage:
# ./02.administrators_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The administrator is example_admin, with the role example_role: run
#   20.AdministrativeRoles/02.administrativeRoles_POST.sh first.
#   ADMIN_PASSWORD is read from the environment, so export it first:
#     export ADMIN_PASSWORD='the password'
# - Confirmed directly: parent - the administrator it is created under - is
#   needed, though the API reference does not mark it required. Without it:
#   400 "Please specify parent administrator". Here it is ST_USER.
# - 07.administrators_name_DELETE.sh removes it again.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="example_admin"
ROLE="example_role"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-change_me}"

BODY=$(jq -n --arg name "${ADMIN}" --arg role "${ROLE}" --arg parent "${ST_USER}" --arg password "${ADMIN_PASSWORD}" \
  '{loginName: $name, roleName: $role, parent: $parent, localAuthentication: true,
    passwordCredentials: {password: $password}}')

printf "Creating the administrator %s, role %s...\n" "${ADMIN}" "${ROLE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
[ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
printf 'HTTP %s\n' "${HTTP_CODE}"
[ "${HTTP_CODE}" = "201" ]
