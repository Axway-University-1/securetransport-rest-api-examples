#!/bin/bash
# ==============================================================================
# Script Name: 31.configurations_fileArchiving_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes how long archived files are kept, using the
# `/configurations/fileArchiving` endpoint with PATCH.
#
# Usage:
# ./31.configurations_fileArchiving_PATCH.sh DAYS
#
#   DAYS  delete archived files older than this many days
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the value before, to put back with.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which reads the value.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
DAYS="$1"
[[ "${DAYS}" =~ ^[1-9][0-9]*$ ]] || { printf "Usage: ./31.configurations_fileArchiving_PATCH.sh DAYS\n"; exit 2; }

printf "Archived files are now deleted after %s.\n" "$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/fileArchiving" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '"\(.deleteFilesOlderThan) \(.deleteFilesOlderThanUnit)"')"

printf "Setting it to %s days...\n" "${DAYS}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/fileArchiving" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -w "\n%{http_code}" \
  -d "[{\"op\":\"replace\",\"path\":\"/deleteFilesOlderThan\",\"value\":${DAYS}},{\"op\":\"replace\",\"path\":\"/deleteFilesOlderThanUnit\",\"value\":\"days\"}]")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
