#!/bin/bash
# ==============================================================================
# Script Name: 28.configurations_keystorePassword_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes the password of the server's keystore, using the
# `/configurations/keystorePassword` endpoint with PUT: the old password, and
# the new one twice.
#
# Usage:
# ./28.configurations_keystorePassword_PUT.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - NOT RUN on the shared lab these examples were checked against: it changes
#   the whole server, and cannot simply be undone. Its request is checked
#   offline, against a stub.
# - OLD_KEYSTORE_PASSWORD and NEW_KEYSTORE_PASSWORD are read from the
#   environment, so export them first:
#     export OLD_KEYSTORE_PASSWORD='the current password'
#     export NEW_KEYSTORE_PASSWORD='the new password'
# - Keep the new password safe: the keystore holds the server's private keys.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
if [ -z "${OLD_KEYSTORE_PASSWORD}" ] || [ -z "${NEW_KEYSTORE_PASSWORD}" ]; then
    printf "Set OLD_KEYSTORE_PASSWORD and NEW_KEYSTORE_PASSWORD first.\n"
    exit 2
fi
BODY=$(jq -cn --arg old "${OLD_KEYSTORE_PASSWORD}" --arg new "${NEW_KEYSTORE_PASSWORD}" \
  '{oldPassword: $old, newPassword: $new, confirmPassword: $new}')

printf "Changing the keystore password...\n"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/keystorePassword" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
