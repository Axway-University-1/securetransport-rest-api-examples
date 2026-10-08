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
# [export ADMIN_PASSWORD='the password of example_admin']
# ./02.administrators_POST.sh
#
#   ADMIN_PASSWORD  the password of example_admin, from the environment (optional): when it is not set, one is generated and printed
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The administrator is example_admin, with the role example_role: run
#   20.AdministrativeRoles/02.administrativeRoles_POST.sh first.
#   ADMIN_PASSWORD is read from the environment (export it first). It is never in the file: when it is not set, a password is generated (12 random
#   letters and digits after a fixed beginning that satisfies a password policy) and printed once.
# - Confirmed directly: parent - the administrator it is created under - is
#   needed, though the API reference does not mark it required. Without it:
#   400 "Please specify parent administrator". Here it is ST_USER.
# - 07.administrators_name_DELETE.sh removes it again.
# - Requires `jq`, which builds the body.
# - Confirmed directly: a success is 201 with no body and the administrator's address in `Location`. An administrator that exists is 409 "Entry already
#   exist.", a role that does not exist 400 "An admin role with the specified roleName not found.", an empty password 400 "The password cannot be empty.", and a
#   name with a space 400 "Spaces are not allowed in an Administrator Name.". Nothing is created by a refusal.
# - Exit codes: 0 when the administrator was created (201), 1 when the server refuses.
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
PASSWORD="${ADMIN_PASSWORD}"
GENERATED=""
if [ -z "${PASSWORD}" ]; then
    PASSWORD="Ex1!$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)"
    GENERATED="yes"
fi

BODY=$(jq -n --arg name "${ADMIN}" --arg role "${ROLE}" --arg parent "${ST_USER}" --arg password "${PASSWORD}" \
  '{loginName: $name, roleName: $role, parent: $parent, localAuthentication: true,
    passwordCredentials: {password: $password}}')

printf "Creating the administrator %s, role %s...\n" "${ADMIN}" "${ROLE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf 'HTTP %s\n' "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
if [ -n "${GENERATED}" ]; then
    printf "The password of %s is %s (generated: it is not shown again).\n" "${ADMIN}" "${PASSWORD}"
fi
