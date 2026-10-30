#!/bin/bash
# ==============================================================================
# Script Name: 02.transfers_GET_filtered.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Asks for only some transfers: by status, by direction, by protocol, from a time on. The filters go in the query, and a filter that can take several values (status) is repeated. This prints how many each one finds.
#
# Usage:
# ./02.transfers_GET_filtered.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/05.Transfers/01.transfers_GET.sh.
# - startTimeAfter takes a date in RFC 2822 form (what date -R prints), not 2026-10-15: the plain date is refused with 400.
# - A filter that matches nothing is an empty list with HTTP 200, not an error.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

# count NAME QUERY...: how many transfers a set of filters finds (the newest 100 are counted: the script asks for limit=100)
count() {
    local name="$1"; shift
    local result code
    result=$(curl -k -s -G -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/transfers" "$@" --data-urlencode "limit=100" -H "accept: application/json" -H "Referer: ${REFERER}")
    code=${result: -3}
    [[ "${code}" == 200 ]] || { echo "${name}: HTTP ${code}"; st_refused "${code}"; exit 1; }
    printf '%-34s %s\n' "${name}:" "$(echo "${result%???}" | jq 'length')"
}

# Today's midnight, in RFC 2822 (the form the server wants; the date command differs on macOS and Linux)
if date -v0H >/dev/null 2>&1; then
    TODAY=$(date -v0H -v0M -v0S -R)
else
    TODAY=$(date -d "today 00:00:00" -R)
fi
count "all"                         
count "direction Outgoing"            --data-urlencode "direction=Outgoing"
count "direction Incoming"            --data-urlencode "direction=Incoming"
count "protocol http"                 --data-urlencode "protocol=http"
count "failed or aborted"           --data-urlencode "status=Failed" --data-urlencode "status=Aborted"
count "started since midnight"        --data-urlencode "startTimeAfter=${TODAY}"
