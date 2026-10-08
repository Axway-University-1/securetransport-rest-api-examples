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
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It deletes example_role, which 02.administrativeRoles_POST.sh creates. Only
#   ever point it at a role you created.
# - Confirmed directly: with targetRoleName, the role's administrators hold the
#   target role afterwards, and the delete answers 204.
# - Confirmed directly: a role that does not exist is 404 "No such administrative role.", and so is a targetRoleName that does not exist; in
#   both cases nothing is deleted or moved.
# - Requires `jq`, which prints the reason when the server refuses.
# - What is deleted is printed first: the role is read, with its menus and the administrators that hold it (they are moved to TARGET_ROLE, or the
#   server refuses), so that it can be created again with 02.administrativeRoles_POST.sh. A role that cannot be read stops the script (exit 1).
# - Exit codes: 0 when the role was deleted (204), 1 when the server refuses, 2 when there are too many arguments (nothing is sent).
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
if [ "$#" -gt 1 ]; then
    printf "Usage: ./07.administrativeRoles_name_DELETE.sh [TARGET_ROLE]\n"
    exit 2
fi

# Read the role first, to say what is being deleted
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ROLE}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the role %s (HTTP %s), so nothing was deleted.\n" "${ROLE}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
MENUS=$(printf '%s' "${RESPONSE}" | jq -r '(.menus // []) | join(", ")')
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators" \
  --data-urlencode "roleName=${ROLE}" --data-urlencode "fields=loginName" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" = "200" ]; then
    HOLDERS=$(printf '%s' "${RESPONSE}" | jq -r '[(.result // [])[] | .loginName] | join(", ")')
    [ -n "${HOLDERS}" ] || HOLDERS="nobody"
else
    HOLDERS="unknown, HTTP ${HTTP_CODE}"
fi

QUERY=()
if [ -n "${TARGET_ROLE}" ]; then
    QUERY=(-G --data-urlencode "targetRoleName=${TARGET_ROLE}")
    printf "Deleting the role %s (menus: %s; held by: %s), moving its administrators to %s...\n" "${ROLE}" "${MENUS:--}" "${HOLDERS}" "${TARGET_ROLE}"
else
    printf "Deleting the role %s (menus: %s; held by: %s)...\n" "${ROLE}" "${MENUS:--}" "${HOLDERS}"
fi
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ROLE}" "${QUERY[@]}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
