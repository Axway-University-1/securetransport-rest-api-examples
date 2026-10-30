#!/bin/bash
# ==============================================================================
# Script Name: 10.usage_per_business_unit_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 2, usage per business unit, step 5: the usage of one unit. The report has no business unit, so the unit is read from what has one: GET /accounts?businessUnit= for its accounts, GET /logs/transfers with
# businessUnit= for its transfers (all, billable and incoming) after a given time, the same count for each account with account=, and the active users list narrowed to the names of the accounts.
# The accounts must add up to the unit: the script says if they do not.
#
# Usage:
# ./10.usage_per_business_unit_GET.sh [BU] [FROM]
#
#   BU    the business unit (default example_use_bu1)
#   FROM  count the transfers that started after this time, RFC 2822 with its offset, between quotes
#         (default: the time that 07 kept in state.local.window, or else midnight today on this machine)
#
# Risk: read
#
# Notes:
# - Written for this use case, from 09 (the accounts of a unit), 04 (the billable count with totalCount, never returnCount) and 02 (the active users list, read whole and picked by name).
# - It prints one line that ends it: "Business unit NAME: N accounts, T transfers, B billable (I incoming), U active users." 11 prints the same numbers for every unit.
# - The billable count is the one the usage report counts as ST.Transfers, cut to the unit: every inbound transfer, and every outbound one after the first of its chain.
# - The active users are looked up by exact name in the list of the last 60 days: the name filter of activeUsers is a "contains" match, and the list is by name, not by account.
# - Exit 0 when the unit was read and its accounts add up; 1 when a call was refused or the accounts do not add up to the unit; 2 for a wrong parameter (nothing is sent).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./10.usage_per_business_unit_GET.sh [BU] [FROM]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: BU and FROM.\n%s\n" "$#" "${USAGE}"; exit 2; fi
BU="${1:-${BU1}}"
uc_check_bu "${BU}" "${USAGE}"
if [ -n "${2:-}" ]; then
    FROM="$2"
elif [ -s "${WINDOW_FILE}" ]; then
    FROM=$(cat "${WINDOW_FILE}")
else
    FROM=$(uc_midnight 0)
fi
uc_check_window "${FROM}" "${USAGE}"
st_session

echo "Business unit ${BU}, transfers after ${FROM}"
uc_get accounts "businessUnit=${BU}" "limit=1000" "fields=name"
if [ "${LIST_CODE}" != "200" ]; then printf "GET /accounts?businessUnit=%s: HTTP %s: %s\n" "${BU}" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
ACCOUNTS=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount')
NAMES=$(printf '%s' "${LIST_BODY}" | jq -r '.result[].name')

WINDOW=("businessUnit=${BU}" "startTimeAfter=${FROM}" "limit=1" "fields=id")
uc_count "the transfers of ${BU}" logs/transfers "${WINDOW[@]}" || exit 1
TOTAL="${COUNT}"
uc_count "the billable transfers of ${BU}" logs/transfers "isBillable=true" "${WINDOW[@]}" || exit 1
BILLABLE="${COUNT}"
uc_count "the incoming transfers of ${BU}" logs/transfers "incoming=true" "${WINDOW[@]}" || exit 1
INCOMING="${COUNT}"
echo "The log, with businessUnit=${BU}: ${TOTAL} transfers, ${BILLABLE} billable, ${INCOMING} incoming."

SUM=0
SUM_ALL=0
while IFS= read -r NAME; do
    [ -n "${NAME}" ] || continue
    uc_count "the transfers of ${NAME}" logs/transfers "account=${NAME}" "startTimeAfter=${FROM}" "limit=1" "fields=id" || exit 1
    ALL="${COUNT}"
    uc_count "the billable transfers of ${NAME}" logs/transfers "account=${NAME}" "isBillable=true" "startTimeAfter=${FROM}" "limit=1" "fields=id" || exit 1
    echo "  ${NAME}: ${ALL} transfers, ${COUNT} billable"
    SUM=$((SUM + COUNT))
    SUM_ALL=$((SUM_ALL + ALL))
done <<< "${NAMES}"

uc_get statisticsSummary/activeUsers "limit=1000"
if [ "${LIST_CODE}" != "200" ]; then printf "GET /statisticsSummary/activeUsers: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
ACTIVE=$(jq -n --argjson active "${LIST_BODY}" --arg names "${NAMES}" '($names | split("\n") | map(select(length > 0))) as $n | [$active.result[].name | select(. as $x | $n | index($x))] | length')

if [ "${SUM_ALL}" != "${TOTAL}" ] || [ "${SUM}" != "${BILLABLE}" ]; then
    echo "The accounts do not add up to the unit: ${SUM_ALL} transfers and ${SUM} billable for the accounts, ${TOTAL} and ${BILLABLE} for the unit. An account may have moved to or from the unit since."
    exit 1
fi
echo "The accounts add up to the unit."
echo "Business unit ${BU}: ${ACCOUNTS} accounts, ${TOTAL} transfers, ${BILLABLE} billable (${INCOMING} incoming), ${ACTIVE} active users."
