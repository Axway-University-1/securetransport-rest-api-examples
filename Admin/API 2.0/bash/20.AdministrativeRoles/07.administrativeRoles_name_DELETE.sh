#!/bin/bash
# ==============================================================================
# Script Name: 07.administrativeRoles_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes an administrative role, using the
# `/administrativeRoles/{name}` endpoint. It demonstrates:
# - Moving the role's administrators to another role as it goes, with
#   targetRoleName
#
# Usage:
# ./07.administrativeRoles_name_DELETE.sh [TARGET_ROLE]
#
#   TARGET_ROLE  the role the administrators that hold example_role move to.
#                Without it, a role still held is not deleted.
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It deletes example_role, which 02.administrativeRoles_POST.sh creates. Only
#   ever point it at a role you created.
# - Confirmed directly: with targetRoleName, the role's administrators hold the
#   target role afterwards, and the delete answers 204.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrativeRoles"
ROLE="example_role"
TARGET_ROLE="$1"

QUERY=()
if [ -n "${TARGET_ROLE}" ]; then
    QUERY=(-G --data-urlencode "targetRoleName=${TARGET_ROLE}")
    printf "Deleting the role %s, moving its administrators to %s...\n" "${ROLE}" "${TARGET_ROLE}"
else
    printf "Deleting the role %s...\n" "${ROLE}"
fi
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ROLE}" "${QUERY[@]}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
