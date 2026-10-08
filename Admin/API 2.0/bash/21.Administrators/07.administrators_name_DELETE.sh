#!/bin/bash
# ==============================================================================
# Script Name: 07.administrators_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes an administrator, using the `/administrators/{name}`
# endpoint.
#
# Usage:
# ./07.administrators_name_DELETE.sh [ADMIN]
#
#   ADMIN  the login name (default example_admin, which 02.administrators_POST.sh creates)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It deletes example_admin, which 02.administrators_POST.sh creates. Only ever
#   point it at an administrator you created: any can be named, and the delete cannot be undone.
# - Its API keys go with it.
# - THE ADMINISTRATOR YOU LOG IN AS (ST_USER) IS NEVER DELETED: the script refuses that name, whatever its case, with exit 2 before sending anything. Confirmed
#   directly that the server refuses it too: an administrator that deletes itself gets 400 "Administrator cannot be deleted." (tried with a throwaway one).
# - The administrator is read first and what it is (role, parent, locked) is printed, so that it can be created again with 02.administrators_POST.sh. One
#   that cannot be read (404 "Admin not found - X") stops the script with exit 1 and nothing is deleted.
# - Requires `jq`, which URL-encodes the login name and reads the administrator.
# - Confirmed directly: a delete is 204 with no body. An administrator that is not there is 404 on the read and on the delete.
# - Exit codes: 0 when the administrator was deleted (204), 1 when the server refuses or it cannot be read, 2 when the name is empty, is the one logged
#   in as, or there are too many arguments (nothing is sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="${1:-example_admin}"
if [ "$#" -gt 1 ] || [ -z "${ADMIN// /}" ]; then
    printf "Usage: ./07.administrators_name_DELETE.sh [ADMIN]\n"
    exit 2
fi
if [ "$(printf '%s' "${ADMIN}" | tr 'A-Z' 'a-z')" = "$(printf '%s' "${ST_USER}" | tr 'A-Z' 'a-z')" ]; then
    printf "%s is the administrator this script logs in as. It is never deleted.\n" "${ADMIN}"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${ADMIN}" '$name | @uri')

# Read it first, to say what is being deleted
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the administrator %s (HTTP %s), so nothing was deleted.\n" "${ADMIN}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi

printf "Deleting the administrator %s (%s)...\n" "${ADMIN}" "$(printf '%s' "${RESPONSE}" | jq -r '"role \(.roleName), created by \(.parent // "-"), locked \(.locked)"')"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
