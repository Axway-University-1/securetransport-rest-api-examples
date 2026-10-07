#!/bin/bash
# ==============================================================================
# Script Name: 05.administrators_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces an administrator, using the `/administrators/{name}`
# endpoint with PUT: it reads the administrator, unlocks it, and sends the
# whole administrator back.
#
# Usage:
# ./05.administrators_name_PUT.sh [ADMIN]
#
#   ADMIN  the login name (default example_admin)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - 06.administrators_name_PATCH.sh locks it; this unlocks it.
# - The read-only parts are left out of what is sent: metadata, and the API
#   keys, which have their own endpoint (08 to 10 in this folder).
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which edits the administrator.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="${1:-example_admin}"

ADMIN_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ADMIN}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${ADMIN_JSON}" | jq -e '.loginName' >/dev/null 2>&1; then
    printf "There is no administrator %s.\n" "${ADMIN}"
    exit 1
fi
BODY=$(printf '%s' "${ADMIN_JSON}" | jq -c '.locked = false | del(.metadata, .apiKeys)')

printf "Unlocking %s...\n" "${ADMIN}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${ADMIN}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
