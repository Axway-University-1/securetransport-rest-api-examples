#!/bin/bash
# ==============================================================================
# Script Name: 01.administrativeRoles_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the administrative roles using the `/administrativeRoles`
# endpoint. A role is the set of Admin UI menus - and with them, API resources -
# an administrator may use. It demonstrates:
# - Listing the roles, a page at a time
# - Filtering: only the limited roles
# - Asking for some fields only, with fields=
#
# Usage:
# ./01.administrativeRoles_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - roleName, isLimited, isBounceAllowed and menus filter too.
# - Confirmed directly: fields=roleType is refused ("Field roleType does not
#   exist."), although a role read whole carries roleType.
# - Each role has a link to its members: the administrators that hold it.
# - Requires `jq`, which prints one role per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrativeRoles"
printf "The first 5 roles:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=5&offset=0" -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nThe limited roles, one line each: name, the menus they open:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?isLimited=true&fields=roleName,menus" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.roleName): \(.menus | join(", "))"'
