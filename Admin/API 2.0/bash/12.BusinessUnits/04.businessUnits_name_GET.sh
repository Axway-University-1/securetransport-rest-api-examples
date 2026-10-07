#!/bin/bash
# ==============================================================================
# Script Name: 04.businessUnits_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads a business unit, using the `/businessUnits/{name}`
# endpoint, and counts the accounts in it, with /accounts?businessUnit=.
#
# Usage:
# ./04.businessUnits_name_GET.sh [NAME]
#
#   NAME  the business unit (default Finance, which 01.businessUnits_POST.sh
#         creates)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: metadata.links.accounts and .applications are ready made
#   searches for the accounts and applications in the unit, but the server
#   encodes them wrongly for a name with a space (businessUnit=example%2Bbu
#   finds nothing). This script searches by the name itself instead.
# - Confirmed directly: a nested unit also carries
#   metadata.links.parentBusinessUnit.
# - Requires `jq`, which URL-encodes the name and reads the answer.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/businessUnits"
NAME="${1:-Finance}"
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read %s (HTTP %s):\n%s\n" "${NAME}" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"

printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '"  \(.businessUnitHierarchy), base folder \(.baseFolder)"'
COUNT=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" \
  --data-urlencode "businessUnit=${NAME}" --data-urlencode "limit=1" --data-urlencode "fields=name" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.resultSet.totalCount // 0')
printf "  accounts in it: %s\n" "${COUNT}"
