#!/bin/bash
# ==============================================================================
# Script Name: 05.sessions_statistics_userClass_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads how many sessions are open for each user class, using the
# `/sessions/statistics/userClass` endpoint: the count by protocol on the whole server (and on this
# node), the bandwidth in use and the limit.
#
# Usage:
# ./05.sessions_statistics_userClass_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which prints one line per user class.
# - Confirmed directly: the answer is a plain array of the two classes the server always has, VirtClass (the
#   accounts the server holds itself, which is every account made through the API) and RealClass (system users).
#   It is NEVER empty, unlike the session list: with no client connected every count is 0.
# - Confirmed directly: the counts follow the sessions as they open and close. With an FTP and an HTTP session of one
#   test account open, VirtClass read total 2, ftp 1, http 1; after the FTP one was ended it read 1. An SSH session
#   is counted as ssh. `globalLoggedInCounters` is the cluster, `localLoggedInCounters` this node: the same on a
#   standalone server.
# - Confirmed directly: `maxAllowed` is `unlimited` (or a number as text), `instantaneousFTPBandwidth` was `N/A`, and
#   `bandwidthUsageStats` (inbound, outbound) 0 even while a client uploaded. `fields=userClass` keeps one key per class.
# - Exit codes: 0 when the server answered 200, 1 when it refuses.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sessions/statistics/userClass"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi

printf '%s' "${RESPONSE}" | jq -r '
  "Sessions by user class: \(length) classes",
  "",
  "User class, sessions on the server (ftp, http, ssh), on this node, bandwidth in and out, the most allowed:",
  (.[] | "  \(.userClass)  \(.globalLoggedInCounters.total) sessions (ftp \(.globalLoggedInCounters.ftp), http \(.globalLoggedInCounters.http), ssh \(.globalLoggedInCounters.ssh))  here \(.localLoggedInCounters.total)  in \(.bandwidthUsageStats.inbound), out \(.bandwidthUsageStats.outbound)  max \(.maxAllowed)")'
