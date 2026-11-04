#!/bin/bash
# ==============================================================================
# Script Name: 01.transfers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# API 1.4, step 1: look at what the bulk resubmit would touch. `POST /api/v1.4/transfers/resubmit` takes the same search criteria as `GET /api/v1.4/transfers`, so the safe way to use it is to
# make the GET first, with exactly the criteria you will give the POST, and read the list. This script does that for an account.
#
# Usage:
# ./01.transfers_GET.sh [ACCOUNT]
#
#   ACCOUNT  the account whose transfers to list (default: example_rsb_b)
#
# Risk: read
#
# Notes:
# - Written for this use case. The API 1.4 answers a list as {"transferEntries": [{"transferEntry": {...}}]}, not {resultSet, result}.
# - The criteria are accountOrLogin (the account), resubmitted=false (not resubmitted yet) and startTimeAfter (the time kept by 02), with limit=100: 1.4 refuses a call without a limit ("Parameter limit
#   should be a positive integer."). 02 sends the same.
# - Confirmed directly: the file criterion is an exact file name (file=report_1.txt), not a pattern: file=report_* finds nothing. That is why the criterion here is the account.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/../lib.sh"
USAGE="Usage: ./01.transfers_GET.sh [ACCOUNT]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: ACCOUNT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
ACCOUNT="${1:-${A14}}"
uc_check_account "${ACCOUNT}" "${USAGE}"

QUERY=("accountOrLogin=${ACCOUNT}" "resubmitted=false" "limit=100")
FROM=$(uc_window)
[ -n "${FROM}" ] && QUERY+=("startTimeAfter=${FROM}")
uc14_call GET transfers "${QUERY[@]}"
if [ "${LIST_CODE}" != "200" ]; then
    printf "GET /api/v1.4/transfers: HTTP %s: %s\n" "${LIST_CODE}" "$(printf '%s' "${LIST_BODY}" | jq -r '(.validationErrors[0] // .message // .)' 2>/dev/null)"
    exit 1
fi
COUNT=$(printf '%s' "${LIST_BODY}" | jq -r '.transferEntries | length')
printf "A resubmit with accountOrLogin=%s, resubmitted=false%s would touch %s transfers:\n" "${ACCOUNT}" "${FROM:+, startTimeAfter=${FROM}}" "${COUNT}"
printf '%s' "${LIST_BODY}" | jq -r '.transferEntries[].transferEntry | "  \(.filename)  \(.status)  \(.direction)  resubmitted: \(.resubmitted)"'
[ "${COUNT}" -gt 0 ] || { echo "There are none: run 02.uploads_POST.sh first."; exit 1; }
