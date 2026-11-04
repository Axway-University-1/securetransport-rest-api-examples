#!/bin/bash
# ==============================================================================
# Script Name: 03.check_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# API 1.4, step 3: check what the resubmit did, with the API 1.4 itself: `GET /api/v1.4/transfers` shows each transfer that was resubmitted flagged `resubmitted: true`, and the new transfers after
# it. The script waits up to 30 seconds for the new ones, then prints the counts.
#
# Usage:
# ./03.check_GET.sh [ACCOUNT]
#
#   ACCOUNT  the account whose log to read (default: example_rsb_b)
#
# Risk: read
#
# Notes:
# - Written for this use case. The same check as 2.0/03.check_GET.sh, read through the other API.
# - Every transfer that is flagged has a copy, so the transfers that are not flagged are at least as many as the flagged ones. The script exits 0 when that holds and something was flagged,
#   1 when nothing was resubmitted, or the copies did not come.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/../lib.sh"
USAGE="Usage: ./03.check_GET.sh [ACCOUNT]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: ACCOUNT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
ACCOUNT="${1:-${A14}}"
uc_check_account "${ACCOUNT}" "${USAGE}"

QUERY=("accountOrLogin=${ACCOUNT}" "limit=100")
FROM=$(uc_window)
[ -n "${FROM}" ] && QUERY+=("startTimeAfter=${FROM}")
for ATTEMPT in $(seq 1 30); do
    uc14_call GET transfers "${QUERY[@]}"
    if [ "${LIST_CODE}" != "200" ]; then
        printf "GET /api/v1.4/transfers: HTTP %s: %s\n" "${LIST_CODE}" "$(printf '%s' "${LIST_BODY}" | jq -r '(.validationErrors[0] // .message // .)' 2>/dev/null)"
        exit 1
    fi
    TOTAL=$(printf '%s' "${LIST_BODY}" | jq -r '.transferEntries | length')
    FLAGGED=$(printf '%s' "${LIST_BODY}" | jq -r '[.transferEntries[].transferEntry | select(.resubmitted == true)] | length')
    [ "${FLAGGED}" -eq 0 ] && break
    [ $((TOTAL - FLAGGED)) -ge "${FLAGGED}" ] && break
    sleep 1
done
printf '%s' "${LIST_BODY}" | jq -r '.transferEntries[].transferEntry | "  \(.filename)  \(.status)  resubmitted: \(.resubmitted)"'
echo "${TOTAL} transfers in the log: ${FLAGGED} flagged as resubmitted, $((TOTAL - FLAGGED)) not flagged (the originals not resubmitted, and the new transfers the resubmit made)."
if [ "${FLAGGED}" -eq 0 ]; then echo "Nothing was resubmitted."; exit 1; fi
if [ $((TOTAL - FLAGGED)) -lt "${FLAGGED}" ]; then echo "After 30 seconds the log has fewer new transfers than resubmitted ones."; exit 1; fi
echo "Every resubmitted transfer has a new transfer after it."
