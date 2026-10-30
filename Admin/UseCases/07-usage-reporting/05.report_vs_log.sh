#!/bin/bash
# ==============================================================================
# Script Name: 05.report_vs_log.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 1, global usage, step 5: the usage report against the transfer log. For each day, ST.Transfers of generateReport and the number of billable transfers that GET /logs/transfers counts for the same day, side by side with the
# difference. The two can differ: that is what this step shows, and it is not a failure. The numbers of a report or an invoice come from the report.
#
# Usage:
# ./05.report_vs_log.sh [DAYS]
#
#   DAYS  how many days to compare, today included (default 3)
#
# Risk: read
#
# Notes:
# - Written for this use case, from 03 (the report of one day: its dd/MM/yyyy day and the answer's ST.Transfers) and 04 (the billable count of the same day, with the same midnight to midnight window).
# - On the lab the two were equal on some days and a few apart on others. ST.TransfersOut could not be rebuilt from the log at all: see the README.
# - Exit 0 when every day could be read, 1 when a call was refused, 2 for a wrong parameter (nothing is sent).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./05.report_vs_log.sh [DAYS]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: DAYS.\n%s\n" "$#" "${USAGE}"; exit 2; fi
DAYS="${1:-3}"
uc_check_days "${DAYS}" "${USAGE}"
st_session

printf "%-12s %12s %12s %10s\n" "Day" "Report" "Log" "Difference"
EQUAL=0
for N in $(seq $((DAYS - 1)) -1 0); do
    DAY=$(uc_ddmmyyyy_ago "${N}")
    uc_get statisticsSummary/generateReport "startDate=${DAY}" "endDate=${DAY}"
    if [ "${LIST_CODE}" != "200" ]; then printf "The report for %s: HTTP %s: %s\n" "${DAY}" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
    REPORT=$(printf '%s' "${LIST_BODY}" | jq -r '.meta.reportSummary["ST.Transfers"] // empty')
    if [[ ! "${REPORT}" =~ ^[0-9]+$ ]]; then printf "The report for %s has no ST.Transfers.\n" "${DAY}"; exit 1; fi
    uc_count "the log for ${DAY}" logs/transfers "isBillable=true" "startTimeAfter=$(uc_midnight "${N}")" "endTimeBefore=$(uc_midnight "$((N - 1))")" "limit=1" "fields=id" || exit 1
    printf "%-12s %12s %12s %+10d\n" "${DAY}" "${REPORT}" "${COUNT}" "$((COUNT - REPORT))"
    [ "${REPORT}" = "${COUNT}" ] && EQUAL=$((EQUAL + 1))
done
echo "The two are equal on ${EQUAL} of ${DAYS} days. Take the numbers for a report or an invoice from the report, and use the log to look at the transfers behind a day."
