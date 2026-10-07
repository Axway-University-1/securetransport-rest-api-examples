#!/bin/bash
# ==============================================================================
# Script Name: 30.configurations_fileArchiving_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces the file archiving settings, using the
# `/configurations/fileArchiving` endpoint with PUT: it reads them, changes the
# largest file archived (maximumFileSizeAllowedToArchive), and sends the whole
# settings back.
#
# Usage:
# ./30.configurations_fileArchiving_PUT.sh MAX_MB
#
#   MAX_MB  the largest file archived, in MB
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the value before, to put back with.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which edits the settings.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
MAX_MB="$1"
[[ "${MAX_MB}" =~ ^[0-9]+$ ]] || { printf "Usage: ./30.configurations_fileArchiving_PUT.sh MAX_MB\n"; exit 2; }

SETTINGS=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/fileArchiving" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${SETTINGS}" | jq -e 'has("maximumFileSizeAllowedToArchive")' >/dev/null 2>&1; then
    printf "Could not read the file archiving settings.\n"
    exit 1
fi
printf "maximumFileSizeAllowedToArchive is now %s.\n" "$(printf '%s' "${SETTINGS}" | jq -r '.maximumFileSizeAllowedToArchive')"
BODY=$(printf '%s' "${SETTINGS}" | jq -c --argjson max "${MAX_MB}" '.maximumFileSizeAllowedToArchive = $max')

printf "Setting it to %s...\n" "${MAX_MB}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/fileArchiving" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
