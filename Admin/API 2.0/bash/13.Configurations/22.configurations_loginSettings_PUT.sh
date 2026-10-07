#!/bin/bash
# ==============================================================================
# Script Name: 22.configurations_loginSettings_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces the login settings, using the
# `/configurations/loginSettings` endpoint with PUT: it reads them, changes how
# deep an administrator's certificate chain may be (adminCertificateDepthLimit),
# and sends the whole settings back.
#
# Usage:
# ./22.configurations_loginSettings_PUT.sh [DEPTH]
#
#   DEPTH  the new adminCertificateDepthLimit (default 10)
#
# Risk: config
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
# - Requires `jq`, which edits the settings.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
DEPTH="${1:-10}"
[[ "${DEPTH}" =~ ^[0-9]+$ ]] || { printf "DEPTH must be a whole number: %s\n" "${DEPTH}"; exit 2; }

SETTINGS=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/loginSettings" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${SETTINGS}" | jq -e 'has("adminCertificateDepthLimit")' >/dev/null 2>&1; then
    printf "Could not read the login settings.\n"
    exit 1
fi
printf "adminCertificateDepthLimit is now %s.\n" "$(printf '%s' "${SETTINGS}" | jq -r '.adminCertificateDepthLimit')"
BODY=$(printf '%s' "${SETTINGS}" | jq -c --argjson depth "${DEPTH}" '.adminCertificateDepthLimit = $depth')

printf "Setting it to %s...\n" "${DEPTH}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/loginSettings" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
