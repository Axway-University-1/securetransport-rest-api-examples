#!/bin/bash
# ==============================================================================
# Script Name: 20.configurations_sentinel_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script turns off reporting to Axway Sentinel, using the
# `/configurations/sentinel` endpoint with PUT: it reads the settings, sets
# enabled and heartbeatEnabled to false, and sends the whole settings back.
#
# Usage:
# ./20.configurations_sentinel_PUT.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The host, port and the other settings stay, ready to turn on again.
# - Confirmed directly: once a host is set, the endpoint refuses an empty one,
#   "host must not be null or empty", even with reporting off, and then any
#   change at all. Turn reporting off first, then set the options behind it with
#   04.configurations_options_PUT.sh: AxwaySentinel.RemoteHost.host and
#   AxwaySentinel.OverflowFile.path to an empty string, and
#   AxwaySentinel.RemoteHost.port and AxwaySentinel.Heartbeat.delay to their
#   values before.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which edits the settings.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
SETTINGS=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/sentinel" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${SETTINGS}" | jq -e 'has("enabled")' >/dev/null 2>&1; then
    printf "Could not read the Sentinel settings.\n"
    exit 1
fi
BODY=$(printf '%s' "${SETTINGS}" | jq -c '.enabled = false | .heartbeatEnabled = false')

printf "Turning off reporting to Sentinel...\n"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/sentinel" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
