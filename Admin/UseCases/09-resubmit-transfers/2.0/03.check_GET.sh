#!/bin/bash
# ==============================================================================
# Script Name: 03.check_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# API 2.0, step 3: check what the resubmit did. The log now shows each transfer that was resubmitted flagged `resubmitted: true`, and a new transfer after it (the resubmit). The script waits up to
# 30 seconds for the new transfers, then prints the counts.
#
# Usage:
# ./03.check_GET.sh [ACCOUNT]
#
#   ACCOUNT  the account whose log to read (default: example_rsb_a)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/16.TransferLogs/01.logs_transfers_GET.sh.
# - Every transfer that is flagged has a copy, so the transfers that are not flagged are at least as many as the flagged ones. The script exits 0 when that holds and something was flagged,
#   1 when nothing was resubmitted, or the copies did not come.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/../lib.sh"
USAGE="Usage: ./03.check_GET.sh [ACCOUNT]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: ACCOUNT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
ACCOUNT="${1:-${A20}}"
uc_check_account "${ACCOUNT}" "${USAGE}"
st_session

QUERY=("account=${ACCOUNT}" "fields=filename,status,resubmitted" "sortByStartTime=ascending" "limit=100")
FROM=$(uc_window)
[ -n "${FROM}" ] && QUERY+=("startTimeAfter=${FROM}")
for ATTEMPT in $(seq 1 30); do
    uc_get logs/transfers "${QUERY[@]}"
    if [ "${LIST_CODE}" != "200" ]; then printf "GET /logs/transfers: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
    TOTAL=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount // 0')
    FLAGGED=$(printf '%s' "${LIST_BODY}" | jq -r '[.result[] | select(.resubmitted == true)] | length')
    [ "${FLAGGED}" -gt 0 ] && [ $((TOTAL - FLAGGED)) -ge "${FLAGGED}" ] && break
    [ "${FLAGGED}" -eq 0 ] && break
    sleep 1
done
printf '%s' "${LIST_BODY}" | jq -r '.result[] | "  \(.filename)  \(.status)  resubmitted: \(.resubmitted)"'
echo "${TOTAL} transfers in the log: ${FLAGGED} flagged as resubmitted, $((TOTAL - FLAGGED)) not flagged (the originals not resubmitted, and the new transfers the resubmits made)."
if [ "${FLAGGED}" -eq 0 ]; then echo "Nothing was resubmitted."; exit 1; fi
if [ $((TOTAL - FLAGGED)) -lt "${FLAGGED}" ]; then echo "After 30 seconds the log has fewer new transfers than resubmitted ones."; exit 1; fi
echo "Every resubmitted transfer has a new transfer after it."
