#!/bin/bash
# ==============================================================================
# Script Name: 04.statisticsSummary_activeUsers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# A long list, read in pages. GET /statisticsSummary/activeUsers lists the users who have logged in. The answer is a page, so this asks for limit and offset: the first page of 5, then the next, and says how many there are in all.
#
# Usage:
# ./04.statisticsSummary_activeUsers_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/33.StatisticsSummary/02.statisticsSummary_activeUsers_GET.sh.
# - Without limit the server sends a page of 100. To read everything, add the limit to the offset until the offset passes totalCount.
# - lastAccessTime is text for people, not a date to parse.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

PAGE=5
offset=0
while [ "${offset}" -lt $((PAGE * 2)) ]; do
    result=$(curl -k -s -G -w "%{http_code}" -b "${JAR}" "${ST_URL}/statisticsSummary/activeUsers"              --data-urlencode "limit=${PAGE}" --data-urlencode "offset=${offset}" -H "accept: application/json" -H "Referer: ${REFERER}")
    code=${result: -3}
    [[ "${code}" == 200 ]] || { echo "HTTP ${code}: ${result%???}"; exit 1; }
    BODY="${result%???}"
    total=$(echo "${BODY}" | jq -r '.resultSet.totalCount')
    echo "Offset ${offset}, ${PAGE} at a time (of ${total} in all):"
    echo "${BODY}" | jq -r '.result[] | "  \(.name)   last login \(.lastAccessTime)"'
    offset=$((offset + PAGE))
    if [ "${offset}" -ge "${total}" ]; then break; fi
done
