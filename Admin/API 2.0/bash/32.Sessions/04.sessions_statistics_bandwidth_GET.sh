#!/bin/bash
# ==============================================================================
# Script Name: 04.sessions_statistics_bandwidth_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the bandwidth the open sessions use, per login name, using the
# `/sessions/statistics/bandwidth` endpoint: the sessions of each, their inbound and outbound rate, and
# the limit they are allowed.
#
# Usage:
# ./04.sessions_statistics_bandwidth_GET.sh [LIMIT]
#
#   LIMIT  the most login names to return, a positive whole number (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which prints one line per login name.
# - Confirmed directly: the answer is a plain array, and EMPTY (`[]`) on the lab while an FTP client uploaded 6 MB
#   and while sessions of several protocols sat idle: the lab has no bandwidth limit set, and this list seems
#   to hold only users that have one. The shape below (loginName, bandwidthUsageStats and maxAllowedBandwidth with
#   inbound and outbound, sessions with total, http, ftp and ssh) is the reference's and was not seen on the lab.
# - Confirmed directly: `limit=0` is 400 "limit should be a positive integer"; `fields=` is accepted.
#   A POST is 405.
# - Exit codes: 0 when the server answered 200, 1 when it refuses, 2 for a wrong argument (nothing is sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sessions/statistics/bandwidth"
LIMIT="$1"
if [ -n "${LIMIT}" ] && { ! [[ "${LIMIT}" =~ ^[0-9]+$ ]] || [ "${LIMIT}" -lt 1 ] || [ -n "$2" ]; }; then
    printf "Usage: 04.sessions_statistics_bandwidth_GET.sh [LIMIT]   (LIMIT is a positive whole number)\n"
    exit 2
fi

if [ -n "${LIMIT}" ]; then
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET -G "${MAIN_URL}" --data-urlencode "limit=${LIMIT}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
else
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" \
      -w "\n%{http_code}")
fi
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi

printf '%s' "${RESPONSE}" | jq -r '
  "Login names using bandwidth: \(length)",
  "",
  "Login name, sessions, inbound and outbound now, the most allowed:",
  (.[] | "  \(.loginName)  \(.sessions.total // 0) sessions (ftp \(.sessions.ftp // 0), http \(.sessions.http // 0), ssh \(.sessions.ssh // 0))  in \(.bandwidthUsageStats.inbound // 0), out \(.bandwidthUsageStats.outbound // 0)  max in \(.maxAllowedBandwidth.inbound // "-"), out \(.maxAllowedBandwidth.outbound // "-")")'
