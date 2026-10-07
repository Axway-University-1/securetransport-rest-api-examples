#!/bin/bash
# ==============================================================================
# Script Name: 03.deniedUsers_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script removes a login name from the denied users using the
# `/deniedUsers/{name}` endpoint: the name can log in again.
#
# Usage:
# ./03.deniedUsers_name_DELETE.sh [LOGIN_NAME]
#
#   LOGIN_NAME  the name to unblock (default example_denied)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This unblocks a login name: only remove the ones you added. The list also
#   holds the names the server blocks by default.
# - The name is case sensitive here, though the list's loginName= filter is not.
# - Confirmed directly: a name that is not in the list answers 400 "No denied user
#   found with login name", not 404. There is no GET or HEAD on one name: both
#   answer 405; read the list with 01.deniedUsers_GET.sh.
# - The name goes into the path URL-encoded once, with jq's @uri, so a name with a
#   space works.
# - Requires `jq`, which URL-encodes the name.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/deniedUsers"
LOGIN_NAME="${1:-example_denied}"
if [ -z "${LOGIN_NAME// /}" ]; then
    printf "LOGIN_NAME must not be empty.\n"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${LOGIN_NAME}" '$name | @uri')

printf "Unblocking %s...\n" "${LOGIN_NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
