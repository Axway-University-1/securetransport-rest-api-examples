#!/bin/bash
# ==============================================================================
# Script Name: 01.serverTime_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the server's clock, using the `/serverTime` endpoint: the
# time the request arrived and the time the answer left, with the server's
# offset from UTC. It also compares the server's clock with this machine's.
#
# Usage:
# ./01.serverTime_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Confirmed directly: the time is ISO-8601 with a numeric offset, for example
#   2026-10-06T12:28:47.787+0300, not with a Z as the API reference shows.
# - Useful before a time-filtered query, such as 05.Transfers/01.transfers_GET.sh
#   with startTimeAfter: the window is the server's clock, not this machine's.
# - Requires `jq`.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/serverTime" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the server time (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
    exit 1
fi
printf '%s\n' "${BODY}"

SERVER_TIME=$(printf '%s' "${BODY}" | jq -r '.responseDepartureTime')
# The server's time in seconds since 1970, from yyyy-MM-ddTHH:mm:ss.SSS+hhmm
SERVER_EPOCH=$(printf '%s' "${SERVER_TIME}" | jq -Rr '
  capture("^(?<t>[^.]+)\\.[0-9]+(?<s>[+-])(?<h>[0-9]{2})(?<m>[0-9]{2})$")
  | (.t + "Z" | fromdateiso8601) - ((.s + "1" | tonumber) * ((.h | tonumber) * 3600 + (.m | tonumber) * 60))' 2>/dev/null)
if [ -n "${SERVER_EPOCH}" ]; then
    printf "The server's clock is %s second(s) from this machine's.\n" "$((SERVER_EPOCH - $(date +%s)))"
fi
