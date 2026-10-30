#!/bin/bash
# ==============================================================================
# Script Name: 11.usage_all_business_units_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 2, usage per business unit, step 6: every business unit in one table, and what the table does not cover. For each unit: its accounts, its transfers and its billable transfers after a given time. Then the same
# count for the whole server, and the difference: the transfers of accounts that are in no business unit. Last, how many accounts are in no unit.
#
# Usage:
# ./11.usage_all_business_units_GET.sh [FROM]
#
#   FROM  count the transfers that started after this time, RFC 2822 with its offset, between quotes
#         (default: the time that 07 kept in state.local.window, or else midnight today on this machine)
#
# Risk: read
#
# Notes:
# - Written for this use case, from 10 (the count of one unit) and 04 (the count of the whole server).
# - GET /businessUnits is read whole (limit=1000). A unit is counted with businessUnit=NAME, never by the name of its accounts.
# - The whole server is counted with no businessUnit filter: it is the same number as the billable transfers of the usage report for the same time, cut where the report cannot cut it (the report has only whole days).
# - The units add up to less than the server when some accounts are in no unit. That is not an error: it is the line "in no business unit".
# - Exit 0 when the table was made, 1 when a call was refused, 2 for a wrong parameter (nothing is sent).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./11.usage_all_business_units_GET.sh [FROM]"
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

# The whole server first: the share of each unit is a share of this number
uc_count "the billable transfers of the server" logs/transfers "isBillable=true" "startTimeAfter=${FROM}" "limit=1" "fields=id" || exit 1
SERVER_BILLABLE="${COUNT}"
uc_count "the transfers of the server" logs/transfers "startTimeAfter=${FROM}" "limit=1" "fields=id" || exit 1
SERVER_TRANSFERS="${COUNT}"
uc_count "the accounts of the server" accounts "limit=1" "fields=name" || exit 1
SERVER_ACCOUNTS="${COUNT}"

uc_get businessUnits "limit=1000" "fields=name"
if [ "${LIST_CODE}" != "200" ]; then printf "GET /businessUnits: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
UNITS=$(printf '%s' "${LIST_BODY}" | jq -r '.result[].name')
echo "Transfers after ${FROM}: which business unit consumed how much (one call for each unit, with isBillable=true and businessUnit=):"
printf "  %-24s %9s %10s %9s %8s\n" "Business unit" "Accounts" "Transfers" "Billable" "Share"
share() { awk -v a="$1" -v b="$2" 'BEGIN { if (b == 0) printf "%7s", "-"; else printf "%6.1f%%", 100 * a / b }'; }
SUM_ACCOUNTS=0
SUM_TRANSFERS=0
SUM_BILLABLE=0
while IFS= read -r BU; do
    [ -n "${BU}" ] || continue
    uc_count "the accounts of ${BU}" accounts "businessUnit=${BU}" "limit=1" "fields=name" || exit 1
    ACCOUNTS="${COUNT}"
    uc_count "the transfers of ${BU}" logs/transfers "businessUnit=${BU}" "startTimeAfter=${FROM}" "limit=1" "fields=id" || exit 1
    TRANSFERS="${COUNT}"
    uc_count "the billable transfers of ${BU}" logs/transfers "businessUnit=${BU}" "isBillable=true" "startTimeAfter=${FROM}" "limit=1" "fields=id" || exit 1
    printf "  %-24s %9s %10s %9s %s\n" "${BU}" "${ACCOUNTS}" "${TRANSFERS}" "${COUNT}" "$(share "${COUNT}" "${SERVER_BILLABLE}")"
    SUM_ACCOUNTS=$((SUM_ACCOUNTS + ACCOUNTS))
    SUM_TRANSFERS=$((SUM_TRANSFERS + TRANSFERS))
    SUM_BILLABLE=$((SUM_BILLABLE + COUNT))
done <<< "${UNITS}"
printf "  %-24s %9s %10s %9s %s\n" "all the units" "${SUM_ACCOUNTS}" "${SUM_TRANSFERS}" "${SUM_BILLABLE}" "$(share "${SUM_BILLABLE}" "${SERVER_BILLABLE}")"
printf "  %-24s %9s %10s %9s %s\n" "in no business unit" "$((SERVER_ACCOUNTS - SUM_ACCOUNTS))" "$((SERVER_TRANSFERS - SUM_TRANSFERS))" "$((SERVER_BILLABLE - SUM_BILLABLE))" "$(share "$((SERVER_BILLABLE - SUM_BILLABLE))" "${SERVER_BILLABLE}")"
printf "  %-24s %9s %10s %9s %s\n" "the whole server" "${SERVER_ACCOUNTS}" "${SERVER_TRANSFERS}" "${SERVER_BILLABLE}" "$(share "${SERVER_BILLABLE}" "${SERVER_BILLABLE}")"
if [ "${SUM_BILLABLE}" = "${SERVER_BILLABLE}" ]; then
    echo "The units add up to all ${SERVER_BILLABLE} billable transfers of the server in this window: every one belongs to an account that is in a business unit."
else
    echo "The units add up to ${SUM_BILLABLE} of the ${SERVER_BILLABLE} billable transfers of the server. The other $((SERVER_BILLABLE - SUM_BILLABLE)) belong to accounts that are in no business unit (or to a unit this table cannot see)."
    echo "The report cannot tell the units apart, and the sum of the units is not the report."
fi
