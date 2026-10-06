#!/bin/bash
# ==============================================================================
# Script Name: 04.administrativeRoles_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads an administrative role, using the
# `/administrativeRoles/{name}` endpoint, and the administrators that hold it,
# through the members link the role carries.
#
# Usage:
# ./04.administrativeRoles_name_GET.sh [ROLE]
#
#   ROLE  the role's name (default example_role)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the role's metadata.links.members is
#   /administrators?roleName=<role>&fields=loginName.
# - Requires `jq`, which URL-encodes the name, reads the link and prints the
#   members.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrativeRoles"
ROLE="${1:-example_role}"
ENCODED=$(jq -rn --arg role "${ROLE}" '$role | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the role %s (HTTP %s):\n%s\n" "${ROLE}" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"

MEMBERS_URL=$(printf '%s' "${RESPONSE}" | jq -r '.metadata.links.members // empty')
if [ -n "${MEMBERS_URL}" ]; then
    printf "\nThe administrators that hold it:\n"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MEMBERS_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" \
      | jq -r '(.result // [])[] | "  " + .loginName'
fi
