#!/bin/bash
# ==============================================================================
# Script Name: 05.icapServers_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces an ICAP server using the `/icapServers/{name}` endpoint with PUT:
# it reads the server, changes the largest file it is sent (maxSize), and sends the
# whole server back.
#
# Usage:
# ./05.icapServers_name_PUT.sh [NAME [MAX_MB]]
#
#   NAME    the server (default example_icap)
#   MAX_MB  the largest file, in MB; 0 is unlimited (default 10)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the value before, to put back with.
# - Confirmed directly: a PUT whose body has another basicSettings.name RENAMES the
#   server (the old name is gone). This script sets the name back to NAME, so it
#   cannot rename.
# - Confirmed directly: the whole of basicSettings, with maxSize and previewSize, is
#   required; a body without previewSize answers 400. metadata is read back and may
#   be sent, or dropped: this script drops it.
# - A name that does not exist answers 400 "does not exist".
# - Requires `jq`, which URL-encodes the name and edits the server.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/icapServers"
NAME="${1:-example_icap}"
MAX_MB="${2:-10}"
[[ "${MAX_MB}" =~ ^[0-9]+$ ]] || { printf "MAX_MB must be a whole number: %s\n" "${MAX_MB}"; exit 2; }
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

SERVER=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${SERVER}" | jq -e '.basicSettings.name' >/dev/null 2>&1; then
    printf "There is no ICAP server %s.\n" "${NAME}"
    exit 1
fi
printf "maxSize of %s is now %s MB.\n" "${NAME}" "$(printf '%s' "${SERVER}" | jq -r '.basicSettings.maxSize')"
BODY=$(printf '%s' "${SERVER}" | jq -c --arg name "${NAME}" --argjson max "${MAX_MB}" 'del(.metadata) | .basicSettings.name = $name | .basicSettings.maxSize = $max')

printf "Setting it to %s MB...\n" "${MAX_MB}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
