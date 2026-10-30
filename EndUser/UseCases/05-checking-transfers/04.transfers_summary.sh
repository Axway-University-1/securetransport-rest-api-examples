#!/bin/bash
# ==============================================================================
# Script Name: 04.transfers_summary.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# A summary of the history: how many transfers there are of each status and of each direction, counted on this side with jq from the list (the newest 100: the script asks for limit=100).
#
# Usage:
# ./04.transfers_summary.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/05.Transfers/01.transfers_GET.sh, with jq added.
# - The server has no summary call: group_by on the list does it.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -G -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/transfers" --data-urlencode "limit=100" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { st_refused "${code}"; exit 1; }
LIST="${result%???}"
echo "Transfers counted: $(echo "${LIST}" | jq 'length')"
echo "By status:"
echo "${LIST}" | jq -r 'group_by(.status)[] | "  \(.[0].status): \(length)"'
echo "By direction:"
echo "${LIST}" | jq -r 'group_by(.direction)[] | "  \(.[0].direction): \(length)"' 
