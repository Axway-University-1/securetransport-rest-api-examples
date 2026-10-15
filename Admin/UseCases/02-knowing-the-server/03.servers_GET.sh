#!/bin/bash
# ==============================================================================
# Script Name: 03.servers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Which servers are defined? GET /servers lists them with their protocol, whether they are active, and their ports, as one line each, and counts them by protocol. A paged answer: the resultSet says how many there are in all.
#
# Usage:
# ./03.servers_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/03.Connect/06.servers_GET.sh.
# - The answer is {resultSet, result}: returnCount is what came back, totalCount how many there are.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/servers" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
BODY="${result%???}"
echo "Servers: $(echo "${BODY}" | jq -r '"\(.resultSet.returnCount) of \(.resultSet.totalCount)"')"
echo "${BODY}" | jq -r '.result[] | "  \(.protocol)\t\(if .isActive then "active" else "not active" end)\t\(.serverName)\tssl port \(.sslListenerPort // "-")"'
echo "By protocol:"
echo "${BODY}" | jq -r '.result | group_by(.protocol)[] | "  \(.[0].protocol): \(length)"' 
