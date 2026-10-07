#!/bin/bash
# ==============================================================================
# Script Name: 19.configurations_sentinel_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script turns on reporting to Axway Sentinel, using the
# `/configurations/sentinel` endpoint with PATCH: the Sentinel host and port,
# a heartbeat, and the file events go to while Sentinel cannot be reached.
#
# Usage:
# ./19.configurations_sentinel_PATCH.sh HOST [PORT]
#
#   HOST  the Sentinel server
#   PORT  its port (default 1305)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the settings before, to put back with
#   20.configurations_sentinel_PUT.sh.
# - Confirmed directly: turning reporting on needs overflowFilePath, a file on
#   the ST server; without it, 400 "overflowFilePath must not be null or
#   empty."
# - Confirmed directly: the server connects at once and sends XML events, a
#   HEARTBEAT every heartbeatDelay seconds. tests/integration/lib/dummy_servers.py
#   has a TcpSink that can stand in for Sentinel.
# - Confirmed directly: once a host is set, the endpoint refuses an empty one,
#   "host must not be null or empty", even with reporting off, and then any
#   change at all. Turn reporting off first, then set the options behind it with
#   04.configurations_options_PUT.sh: AxwaySentinel.RemoteHost.host and
#   AxwaySentinel.OverflowFile.path to an empty string, and
#   AxwaySentinel.RemoteHost.port and AxwaySentinel.Heartbeat.delay to their
#   values before.
# - Requires `jq`, which builds the patch and prints the settings.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
HOST="$1"
PORT="${2:-1305}"
if [ -z "${HOST}" ] || ! [[ "${PORT}" =~ ^[0-9]+$ ]]; then
    printf "Usage: ./19.configurations_sentinel_PATCH.sh HOST [PORT]\n"
    exit 2
fi

printf "Before: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/sentinel" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -c '{enabled, host, port, heartbeatEnabled, heartbeatDelay, overflowFilePath}'

BODY=$(jq -cn --arg host "${HOST}" --argjson port "${PORT}" '[
  {op: "replace", path: "/host", value: $host},
  {op: "replace", path: "/port", value: $port},
  {op: "replace", path: "/overflowFilePath", value: "/tmp/st_sentinel_overflow.dat"},
  {op: "replace", path: "/heartbeatEnabled", value: true},
  {op: "replace", path: "/heartbeatDelay", value: 30},
  {op: "replace", path: "/enabled", value: true}]')

printf "Reporting to Sentinel at %s:%s...\n" "${HOST}" "${PORT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/sentinel" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
