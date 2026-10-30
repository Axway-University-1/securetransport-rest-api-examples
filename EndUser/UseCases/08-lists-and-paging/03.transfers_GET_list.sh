#!/bin/bash
# ==============================================================================
# Script Name: 03.transfers_GET_list.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 3: the list of transfers. GET /transfers answers a plain array, newest first (by start time, to the second), with no wrapper and no count. A call with no limit gives one page of 100, limit=0 gives the same page, and a limit above 100 is
# honoured. The script shows the default page, a limit with an offset, limit=0, and the two limits the server refuses.
#
# Usage:
# ./03.transfers_GET_list.sh [LIMIT]
#
#   LIMIT  entries for the paged call, 1 or more (default 3)
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/05.Transfers/01.transfers_GET.sh.
# - Exit 3 when the account may not use the transfers web service (403). 00.run_all.sh goes on after an exit 3 of this step.
# - 100 is the default page, not a cap: limit=500 returned 105 transfers on the lab. A client that reads one call and stops at 100 loses the rest.
# - limit=-1 is 400 "Parameter should be a positive number or 0." here (the folder list of 02 does not refuse it), and limit=abc is 404 "HTTP 404 Not Found", not 400.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./03.transfers_GET_list.sh [LIMIT]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: LIMIT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
LIMIT="${1:-3}"
eu_check_number "${LIMIT}" LIMIT "${USAGE}"
st_session

# eu_count: the number of entries of the array in EU_BODY, or the reason it is not one
eu_count() { printf '%s' "${EU_BODY}" | jq -r 'if type == "array" then length else "not a list" end' 2>/dev/null; }

eu_get "transfers"
echo "GET /transfers: HTTP ${EU_CODE}"
if [ "${EU_CODE}" = "403" ]; then
    eu_not_allowed
    exit 3
fi
[ "${EU_CODE}" = "200" ] || { eu_why; exit 1; }
if [ "$(eu_count)" = "not a list" ]; then
    echo "The answer is not a plain array."
    exit 1
fi
DEFAULT_COUNT=$(eu_count)
echo "The answer is a plain array of ${DEFAULT_COUNT} entries, no wrapper and no count. Newest first: from $(printf '%s' "${EU_BODY}" | jq -r '.[0].startTime // "-"') down to $(printf '%s' "${EU_BODY}" | jq -r '.[-1].startTime // "-"')."
[ "${DEFAULT_COUNT}" -lt 100 ] || echo "That is the default page of 100. There may be more: ask with an offset."

eu_get "transfers" "limit=${LIMIT}" "offset=1"
echo "limit=${LIMIT}&offset=1: HTTP ${EU_CODE}, $(eu_count) entries, the first is $(printf '%s' "${EU_BODY}" | jq -r '.[0].filename // "-"')."
[ "${EU_CODE}" = "200" ] || { eu_why; exit 1; }

eu_get "transfers" "limit=0"
echo "limit=0: HTTP ${EU_CODE}, $(eu_count) entries: the default page again, not none (the folder list of 02 gives none)."
[ "${EU_CODE}" = "200" ] || { eu_why; exit 1; }

eu_get "transfers" "limit=-1"
echo "limit=-1: HTTP ${EU_CODE}, $(eu_why)"
eu_get "transfers" "limit=abc"
echo "limit=abc: HTTP ${EU_CODE}, $(eu_why)"
