#!/bin/bash
# ==============================================================================
# Script Name: 04.serverTime_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# What time does the server think it is? GET /serverTime returns when the request arrived and when the answer left, in the server's time zone. Useful to see a clock that is off, before it confuses a time window in a query.
#
# Usage:
# ./04.serverTime_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/06.ServerTime/01.serverTime_GET.sh.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/serverTime" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || exit 1
echo "${result%???}" | jq -r '"Request arrived:  " + .requestArrivalTime, "Answer left:      " + .responseDepartureTime'
echo "Your clock:       $(date +%Y-%m-%dT%H:%M:%S%z)"
