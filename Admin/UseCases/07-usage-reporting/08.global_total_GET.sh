#!/bin/bash
# ==============================================================================
# Script Name: 08.global_total_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 2, usage per business unit, step 3: the whole server says how much. After the users worked, the usage report for today (ST.Transfers) is asked again and compared with what it said before (state.local.report), and the
# transfer log counts the billable transfers after the time 07 kept. These are the two global numbers; the question of the administrator is then which business unit consumed which part of them.
#
# Usage:
# ./08.global_total_GET.sh [FROM]
#
#   FROM  count the transfers that started after this time, RFC 2822 with its offset, between quotes
#         (default: the time that 07 kept in state.local.window, or else midnight today on this machine)
#
# Risk: read
#
# Notes:
# - Written for this use case, from 03 (the report of one day) and 04 (the billable count with totalCount).
# - The report has whole days only and no business unit: generateReport takes startDate, endDate and two include flags, and a businessUnit parameter is ignored without a word (the answer is the same as with none).
# - The change in the report is the transfers of every user of the server since 07 started, not only these six accounts: on a server that other people use, it can be more than 100. The same is true of the log count.
# - Exit 0 when both numbers were read, 1 when a call was refused, 2 for a wrong parameter (nothing is sent).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./08.global_total_GET.sh [FROM]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: FROM.\n%s\n" "$#" "${USAGE}"; exit 2; fi
if [ -n "${1:-}" ]; then
    FROM="$1"
elif [ -s "${WINDOW_FILE}" ]; then
    FROM=$(cat "${WINDOW_FILE}")
else
    FROM=$(uc_midnight 0)
fi
uc_check_window "${FROM}" "${USAGE}"
st_session

uc_count "the billable transfers of the server" logs/transfers "isBillable=true" "startTimeAfter=${FROM}" "limit=1" "fields=id" || exit 1
echo "The transfer log, isBillable=true, after ${FROM}: ${COUNT} billable transfers."

if [ -s "${REPORT_FILE}" ]; then
    read -r DAY BEFORE < "${REPORT_FILE}"
    uc_get statisticsSummary/generateReport "startDate=${DAY}" "endDate=${DAY}"
    if [ "${LIST_CODE}" != "200" ]; then printf "The report for %s: HTTP %s: %s\n" "${DAY}" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
    AFTER=$(printf '%s' "${LIST_BODY}" | jq -r '.meta.reportSummary["ST.Transfers"] // empty')
    if [[ ! "${AFTER}" =~ ^[0-9]+$ ]]; then echo "The report for ${DAY} has no ST.Transfers."; exit 1; fi
    echo "The usage report for ${DAY}: ST.Transfers was ${BEFORE} before the users worked and is ${AFTER} now: $((AFTER - BEFORE)) more."
else
    echo "There is no state.local.report: run 07.transfers_make_POST.sh first, and the report can be compared with what it said before."
fi
uc_get statisticsSummary/generateReport "startDate=$(uc_ddmmyyyy_ago 0)" "endDate=$(uc_ddmmyyyy_ago 0)" "businessUnit=${BU1}"
printf "generateReport with businessUnit=%s: HTTP %s, ST.Transfers %s. " "${BU1}" "${LIST_CODE}" "$(printf '%s' "${LIST_BODY}" | jq -r '.meta.reportSummary["ST.Transfers"] // "none"')"
echo "The report has no business unit: that parameter is ignored, and the number is the whole server's."
echo "Which business unit consumed which part of this? 09 to 11 ask the transfer log, which can be filtered by business unit."
