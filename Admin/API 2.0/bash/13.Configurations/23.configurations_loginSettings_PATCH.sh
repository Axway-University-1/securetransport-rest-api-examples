#!/bin/bash
# ==============================================================================
# Script Name: 23.configurations_loginSettings_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes one login setting, using the
# `/configurations/loginSettings` endpoint with PATCH: whether end users must
# give a password (requirePassword).
#
# Usage:
# ./23.configurations_loginSettings_PATCH.sh [VALUE]
#
#   VALUE  optional, required or requiredForUserClasses (default optional);
#          requiredForUserClasses also needs requirePasswordUserClasses
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the value before, to put back with.
# - Confirmed directly: the whole settings are validated on every change. On a
#   server whose settings are already inconsistent - certificateIssuer "other"
#   with no adminCertificateFileOrPath - any PATCH or PUT answers 400 "You must
#   specify adminCertificateFileOrPath when certificateIssuer is set to
#   other.", even one that changes nothing.
# - These settings decide who can log in: try changes on a test server first,
#   and keep a session open to undo them.
# - Requires `jq`, which reads the value.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
VALUE="${1:-optional}"
[[ "${VALUE}" =~ ^(optional|required|requiredForUserClasses)$ ]] \
    || { printf "VALUE is optional, required or requiredForUserClasses, not %s.\n" "${VALUE}"; exit 2; }

printf "requirePassword is now %s.\n" "$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/loginSettings" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.requirePassword')"

printf "Setting it to %s...\n" "${VALUE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/loginSettings" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "[{\"op\":\"replace\",\"path\":\"/requirePassword\",\"value\":\"${VALUE}\"}]" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
