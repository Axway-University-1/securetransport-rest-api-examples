#!/bin/bash
# ==============================================================================
# Script Name: 06.administrators_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script locks an administrator, using the `/administrators/{name}`
# endpoint with PATCH: a JSON Patch document that replaces locked. A locked
# administrator cannot log in.
#
# Usage:
# ./06.administrators_name_PATCH.sh [ADMIN]
#
#   ADMIN  the login name (default example_admin)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - 05.administrators_name_PUT.sh unlocks it again.
# - Confirmed directly: a success answers 204, with no body.
# - Never point it at the administrator you log in as: the script refuses it (exit 2, nothing sent), whatever the case of the name.
# - Requires `jq`, which URL-encodes the login name and builds the patch.
# - Confirmed directly: an administrator that does not exist is 404 "Admin not found - X".
# - Exit codes: 0 when it was locked (204), 1 when the server refuses, 2 when the name is the one logged in as (nothing is sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="${1:-example_admin}"
if [ "$(printf '%s' "${ADMIN}" | tr 'A-Z' 'a-z')" = "$(printf '%s' "${ST_USER}" | tr 'A-Z' 'a-z')" ]; then
    printf "That is the administrator this script logs in as. Not locking it.\n"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${ADMIN}" '$name | @uri')
BODY=$(jq -cn '[{op: "replace", path: "/locked", value: true}]')

printf "Locking %s...\n" "${ADMIN}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
