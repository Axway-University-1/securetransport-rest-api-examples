#!/bin/bash
# ==============================================================================
# Script Name: 07.businessUnits_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a business unit, using the `/businessUnits/{name}`
# endpoint.
#
# Usage:
# ./07.businessUnits_name_DELETE.sh NAME
#
#   NAME  the business unit. There is no default: name the one to delete.
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the server refuses, 400, to delete a unit that still has
#   accounts or nested units; the answer says which. Move or delete those
#   first. Nothing is deleted on a refusal.
# - Requires `jq`, which URL-encodes the name and prints the reason.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/businessUnits"
NAME="$1"
[ -n "${NAME}" ] || { printf "Usage: ./07.businessUnits_name_DELETE.sh NAME\n"; exit 2; }
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

printf "Deleting the business unit %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
