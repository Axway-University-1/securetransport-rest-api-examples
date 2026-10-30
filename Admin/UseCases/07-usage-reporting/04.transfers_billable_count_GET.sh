#!/bin/bash
# ==============================================================================
# Script Name: 04.transfers_billable_count_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 1, global usage, step 4: the billable transfers in the transfer log. GET /logs/transfers with isBillable=true and one window for each day, counted with resultSet.totalCount. Then, for the last day,
# the three values of isBillable (true, false and none), and the filter that is not a filter: accountName=.
#
# Usage:
# ./04.transfers_billable_count_GET.sh [DAYS] [ACCOUNT]
#
#   DAYS     how many days to count, today included (default 3)
#   ACCOUNT  count only the transfers of this account, with account= (default: every account)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/16.TransferLogs/02.logs_transfers_GET_billable.sh, which has the same loop; this step adds the three values of isBillable and the accountName= trap.
# - The count is resultSet.totalCount. With limit=1 the answer holds one transfer, so returnCount is 1 on every day.
# - A day is midnight to midnight on this machine, sent in RFC 2822 with its offset, and asked of date for each midnight: the day the clocks change has 23 or 25 hours. If this machine is not in the
#   time zone of the server, its days are not the server's days.
# - account= is an exact match that ignores case, and * is a wildcard in it. accountName= is not a filter: the answer for an account that does not exist holds every transfer.
# - The rule of what is billable is in Features/audit-billable-transfers: every inbound is billable, the first outbound of a chain is not, each later one is.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./04.transfers_billable_count_GET.sh [DAYS] [ACCOUNT]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: DAYS and ACCOUNT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
DAYS="${1:-3}"
ACCOUNT="${2:-}"
uc_check_days "${DAYS}" "${USAGE}"
st_session

ACCOUNT_FILTER=()
[ -n "${ACCOUNT}" ] && ACCOUNT_FILTER=("account=${ACCOUNT}")
echo "Billable transfers for each day, for ${ACCOUNT:-every account}:"
for N in $(seq $((DAYS - 1)) -1 0); do
    START=$(uc_midnight "${N}")
    END=$(uc_midnight "$((N - 1))")
    uc_count "${START}" logs/transfers "isBillable=true" "${ACCOUNT_FILTER[@]}" "startTimeAfter=${START}" "endTimeBefore=${END}" "limit=1" "fields=id" || exit 1
    echo "  ${START}  ${COUNT}"
done

echo "The three values of isBillable, for the last day (${START}):"
WINDOW=("startTimeAfter=${START}" "endTimeBefore=${END}" "limit=1" "fields=id")
uc_count "all transfers" logs/transfers "${ACCOUNT_FILTER[@]}" "${WINDOW[@]}" || exit 1
ALL="${COUNT}"
uc_count "isBillable=true" logs/transfers "isBillable=true" "${ACCOUNT_FILTER[@]}" "${WINDOW[@]}" || exit 1
BILLABLE="${COUNT}"
uc_count "isBillable=false" logs/transfers "isBillable=false" "${ACCOUNT_FILTER[@]}" "${WINDOW[@]}" || exit 1
FREE="${COUNT}"
echo "  ${ALL} transfers: ${BILLABLE} billable, ${FREE} not billable, $((ALL - BILLABLE - FREE)) with no value (in neither count)."

uc_count "accountName=" logs/transfers "accountName=example_use_no_such_account" "${WINDOW[@]}" || exit 1
echo "accountName=example_use_no_such_account found ${COUNT} of the ${ALL}: accountName is not a filter, and every transfer came back."
uc_count "account=" logs/transfers "account=example_use_no_such_account" "${WINDOW[@]}" || exit 1
echo "account=example_use_no_such_account found ${COUNT}: account is the filter."
