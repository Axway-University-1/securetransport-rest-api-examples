#!/bin/bash
# ==============================================================================
# Script Name: 02.businessUnits_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the business units using the `/businessUnits` endpoint.
# It demonstrates:
# - Listing them, a page at a time
# - Searching by name, with the * wildcard
# - The units nested under another one, with parent=
#
# Usage:
# ./02.businessUnits_GET.sh [PATTERN [PARENT]]
#
#   PATTERN  a name, * matches anything (default *)
#   PARENT   list the units nested under this one (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: baseFolder= is ignored, every value gives every unit.
# - Confirmed directly: parent is always null in an answer, even for a nested
#   unit; businessUnitHierarchy, parent/child, and
#   metadata.links.parentBusinessUnit are where the nesting shows. parent= as a
#   filter does work.
# - Requires `jq`, which prints one unit per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/businessUnits"
PATTERN="${1:-*}"
PARENT="$2"

printf "The first 5 business units:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=5&offset=0" -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nThe units named %s: hierarchy, base folder:\n" "${PATTERN}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${PATTERN}" \
  --data-urlencode "fields=businessUnitHierarchy,baseFolder" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.businessUnitHierarchy)  \(.baseFolder)"'

if [ -n "${PARENT}" ]; then
    printf "\nThe units nested under %s:\n" "${PARENT}"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "parent=${PARENT}" \
      --data-urlencode "fields=name" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '(.result // [])[] | "  " + .name'
fi
