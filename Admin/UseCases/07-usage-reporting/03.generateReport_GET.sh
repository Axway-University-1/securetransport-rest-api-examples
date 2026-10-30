#!/bin/bash
# ==============================================================================
# Script Name: 03.generateReport_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 1, global usage, step 3: the usage report. GET /statisticsSummary/generateReport for a period, one line for each day, and the total. It checks that the total is the sum of the days, then sends
# the four calls the server refuses and checks that each answer is a 400 with its message.
#
# Usage:
# ./03.generateReport_GET.sh [FROM] [TO]
#
#   FROM  the first day, dd/MM/yyyy (default: two days ago)
#   TO    the last day, dd/MM/yyyy, INCLUDED (default: today)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/33.StatisticsSummary/01.statisticsSummary_generateReport_GET.sh, with the four refusals added.
# - The dates are dd/MM/yyyy and nothing else. The days of the report are the server's days, named by the start of the day with the offset of that moment (+03:00 before the clocks go back, +02:00 after).
# - A report you ask for includes today. The automatic report to the Amplify Platform does not (DaysToInclude: not tried here).
# - ST.ActiveUsers and ST.Volume were 0 on the lab in every report, also with the include parameters set to true.
# - Exit 0 when the period was read and the checks held, 1 when the server answered otherwise than expected.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./03.generateReport_GET.sh [FROM] [TO]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: FROM and TO.\n%s\n" "$#" "${USAGE}"; exit 2; fi
FROM="${1:-$(uc_ddmmyyyy_ago 2)}"
TO="${2:-$(uc_ddmmyyyy_ago 0)}"
uc_check_date "${FROM}" "FROM" "${USAGE}"
uc_check_date "${TO}" "TO" "${USAGE}"
st_session

echo "GET /statisticsSummary/generateReport?startDate=${FROM}&endDate=${TO}"
uc_get statisticsSummary/generateReport "startDate=${FROM}" "endDate=${TO}" "includeActiveUsersCount=true" "includeIncomingFileVolume=true"
if [ "${LIST_CODE}" != "200" ]; then printf "HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
REPORT="${LIST_BODY}"
printf '%s' "${REPORT}" | jq -r '
  (.report | to_entries | sort_by(.key)) as $days
  | "Release \(.meta.productVersion), one entry each \((.granularity // 0) / 3600000) hours, \($days | length) days from \(.meta.reportTimeframe.startDate) to \(.meta.reportTimeframe.endDate) (the start of the day after the last day).",
    "Day (as the server names it)           transfers  in  out  users  volume",
    ($days[] | "  \(.key)  \(.value.usage["ST.Transfers"])  \(.value.usage["ST.TransfersIn"])  \(.value.usage["ST.TransfersOut"])  \(.value.usage["ST.ActiveUsers"])  \(.value.usage["ST.Volume"])"),
    "Summary: transfers \(.meta.reportSummary["ST.Transfers"]), in \(.meta.reportSummary["ST.TransfersIn"]), out \(.meta.reportSummary["ST.TransfersOut"]), users \(.meta.reportSummary["ST.ActiveUsers"]), volume \(.meta.reportSummary["ST.Volume"])"'
SUMS=$(printf '%s' "${REPORT}" | jq -r '[ ["ST.Transfers","ST.TransfersIn","ST.TransfersOut"][] as $k | ([.report[].usage[$k]] | add) == .meta.reportSummary[$k] ] | all')
if [ "${SUMS}" = "true" ]; then
    echo "The summary is the sum of the days."
else
    echo "The summary is NOT the sum of the days: the report cannot be trusted as it stands."
    exit 1
fi
printf '%s' "${REPORT}" | jq -r '"ST.ActiveUsers in the summary: \(.meta.reportSummary["ST.ActiveUsers"]), ST.Volume: \(.meta.reportSummary["ST.Volume"]), although both were asked for."'

STATUS=0
refused() {      # LABEL EXPECTED_TEXT PARAM... : the call must be a 400 that says EXPECTED_TEXT
    local label="$1" expected="$2"
    shift 2
    uc_get statisticsSummary/generateReport "$@"
    if [ "${LIST_CODE}" = "400" ] && uc_why | grep -qF -- "${expected}"; then
        printf "Refused, as it should be (%s): HTTP 400, %s\n" "${label}" "$(uc_why | head -1)"
    else
        printf "NOT refused as expected (%s): HTTP %s, %s\n" "${label}" "${LIST_CODE}" "$(uc_why | head -1)"
        STATUS=1
    fi
}
refused "no endDate" "'startDate' and 'endDate' parameters are mandatory." "startDate=${FROM}"
refused "startDate after endDate" "Incorrect date frame. 'startDate' must be before 'endDate'." "startDate=${TO}" "endDate=$(uc_ddmmyyyy_ago 30)"
refused "a day written yyyy-MM-dd" "is not in correct format. The correct format is: dd/MM/yyyy." "startDate=2026-10-23" "endDate=2026-10-24"
refused "a day in the future" "An error occur while generating report" "startDate=$(uc_ddmmyyyy_ago -3)" "endDate=$(uc_ddmmyyyy_ago -4)"
exit ${STATUS}
