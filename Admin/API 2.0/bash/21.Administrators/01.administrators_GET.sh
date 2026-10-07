#!/bin/bash
# ==============================================================================
# Script Name: 01.administrators_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the administrators using the `/administrators` endpoint.
# It demonstrates:
# - Listing them, a page at a time
# - Filtering: the administrators that hold a role, the locked ones
# - Asking for some fields only, with fields=
#
# Usage:
# ./01.administrators_GET.sh [ROLE]
#
#   ROLE  the role to list the administrators of (default Master Administrator)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Many more filters exist: parent, isLimited, localAuthentication,
#   dualAuthentication, the password and login times, and the API keys' dates
#   and permissions. See the API reference.
# - Requires `jq`, which prints one administrator per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ROLE="${1:-Master Administrator}"

printf "The first 5 administrators, login name and role:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=5&offset=0&fields=loginName,roleName" \
  -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nThe ones that hold %s:\n" "${ROLE}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "roleName=${ROLE}" \
  --data-urlencode "fields=loginName,parent,locked" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.loginName)  created by \(.parent // "-")\(if .locked then "  LOCKED" else "" end)"'

printf "\nThe locked ones:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?locked=true&fields=loginName" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '(.result // [])[] | "  " + .loginName'
