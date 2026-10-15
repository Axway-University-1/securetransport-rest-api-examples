#!/bin/bash
# ==============================================================================
# Script Name: 07.sessions_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Who is connected right now? GET /sessions lists the open sessions on the server: the user, the host they come from, the protocol and the time they began. This counts them by protocol and prints one line each.
#
# Usage:
# ./07.sessions_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/32.Sessions/01.sessions_GET.sh.
# - The answer is a plain list (no resultSet). An empty list is HTTP 200 with [], not an error.
# - Ending a session (DELETE /sessions/<id>) is another call, not shown here.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/sessions" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
BODY="${result%???}"
echo "Open sessions: $(echo "${BODY}" | jq 'length')"
echo "By protocol:"
echo "${BODY}" | jq -r 'group_by(.protocol)[] | "  \(.[0].protocol): \(length)"'
echo "Each:"
echo "${BODY}" | jq -r '.[] | "  \(.userName)  from \(.host)  \(.protocol)  since \(.sessionCreationTime)"' 
