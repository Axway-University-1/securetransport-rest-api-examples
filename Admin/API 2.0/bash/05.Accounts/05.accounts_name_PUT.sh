#!/bin/bash
# ==============================================================================
# Script Name: 05.accounts_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script changes the uid of an account, using the `/accounts/{name}` endpoint with the PUT method.
# It demonstrates the easiest way to update more than one property of an object:
# 1. GET the object's content
# 2. edit the parts you want with jq
# 3. PUT the whole object back
#
# Usage:
# ./05.accounts_name_PUT.sh [NAME [NEW_UID]]
#
#   NAME     the account (default example_user, the one 02.accounts_POST.sh creates)
#   NEW_UID  the new uid, a whole number (default 1111)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - PUT replaces the entire object, so all required fields must be preserved: the script sends back the object it read, with only the uid changed.
# - It prints the old uid, and the command that puts it back, before it changes anything. The 41733 that 02.accounts_POST.sh gives is on purpose: see its Notes.
# - Requires `jq`, which is used to edit the retrieved JSON. Editing it with jq rather than with a text substitution targets the exact field and always produces valid JSON.
#   No file is written: the answer is kept in a variable.
# - Confirmed directly: a success is 204 with no body, also when the object is sent back exactly as it was read (the `metadata` links included). A name that is not an
#   account is 404 on the read, so nothing is sent.
# - Exit codes: 0 when the server answered 204, 1 when the account cannot be read or the server refuses, 2 when NEW_UID is not a whole number (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts"
NAME="${1:-example_user}"
NEW_UID="${2:-1111}"
if [ "$#" -gt 2 ] || ! [[ "${NEW_UID}" =~ ^[0-9]{1,9}$ ]]; then
    printf "Usage: 05.accounts_name_PUT.sh [NAME [NEW_UID]]   (NEW_UID is a whole number, 1111 when left out)\n"
    exit 2
fi
NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')

printf "Getting the account %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${NAME_URI}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the account %s: HTTP %s\n" "${NAME}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
OLD_UID=$(printf '%s' "${RESPONSE}" | jq -r '.uid')
printf "The uid of %s is now %s.\n" "${NAME}" "${OLD_UID}"
printf "To put it back: ./05.accounts_name_PUT.sh %s %s\n" "${NAME}" "${OLD_UID}"

printf "Changing the uid to %s...\n" "${NEW_UID}"
BODY=$(printf '%s' "${RESPONSE}" | jq -c --arg newUid "${NEW_UID}" '.uid = $newUid')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${NAME_URI}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
