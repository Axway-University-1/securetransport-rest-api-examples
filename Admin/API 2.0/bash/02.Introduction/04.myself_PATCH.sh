#!/bin/bash
# ==============================================================================
# Script Name: 04.myself_PATCH.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script changes the password of the administrator it logs in as, using the `/myself`
# endpoint with PATCH: a JSON Patch document that replaces `/passwordCredentials/password`.
# It demonstrates:
# - Reading the new password from the environment, never from the file or an argument
# - Building the JSON Patch body with jq, so any character in the password stays valid JSON
# - Checking the HTTP code: 204 is the only success
#
# Usage:
# export ST_NEW_PASSWORD='the new password'
# ./04.myself_PATCH.sh
#
#   ST_NEW_PASSWORD  the new password, from the environment (an argument would show in the process list).
#                    Without it the script prints this usage, sends NOTHING and exits 2
#
# Risk: config - changes the password of the administrator every example logs in as; every later call needs the new one
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - THIS CHANGES THE PASSWORD OF THE ADMINISTRATOR IN ST_USER, the one every example logs in as. From the next call on
#   every example needs the new password: change it in `set_variables.local.sh` (or set_variables.local.bat) as soon as this
#   has run. Run it against a throwaway administrator, as check 13 does, unless that is what you want.
# - The old password is never known to the script, so it cannot print it. To put it back, run this script again with the old
#   password in ST_NEW_PASSWORD, logging in with the new one.
# - Requires `jq`, which builds the request body.
# - The password is never printed. Nothing is sent without ST_NEW_PASSWORD (exit 2).
# - Confirmed directly: a success is 204 with no body, and the old password stops working at once (401) while the new one works at
#   once. The same password again is 204 too. The lab accepted a one-letter password (no complexity rule refused it), and an empty
#   one is 400 "password cannot be empty". Only `/passwordCredentials/password` and `/preferredFileTrackingColumns` can be patched on
#   `/myself` (any other path is 400 "Patch operation is allowed only on fields ..."); a body that is not a list is 400 "Incorrect JSON
#   format"; a wrong current password is a plain 401 "Authentication required."
# - Exit codes: 0 when the server answered 204, 1 when it refuses, 2 when ST_NEW_PASSWORD is not set (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself"
USAGE="Usage: ST_NEW_PASSWORD='the new password' ./04.myself_PATCH.sh"

if [ -z "${ST_NEW_PASSWORD}" ]; then
    printf "This changes the password of %s, the administrator every example logs in as.\n" "${ST_USER}"
    printf "Nothing was sent. To go on, set ST_NEW_PASSWORD to the new password.\n"
    printf "%s\n" "${USAGE}"
    exit 2
fi

BODY=$(jq -cn --arg password "${ST_NEW_PASSWORD}" '[{op: "replace", path: "/passwordCredentials/password", value: $password}]')

printf "Changing the password of %s...\n" "${ST_USER}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf "The password of %s is changed. Every later call needs the new one: put it in set_variables.local.sh.\n" "${ST_USER}"
