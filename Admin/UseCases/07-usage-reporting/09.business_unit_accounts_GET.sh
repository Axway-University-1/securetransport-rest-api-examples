#!/bin/bash
# ==============================================================================
# Script Name: 09.business_unit_accounts_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 2, usage per business unit, step 4: which accounts belong to a unit. GET /accounts?businessUnit=NAME lists them, and the field businessUnit of one account says the same from the other side. It also shows how
# the two APIs answer a unit that does not exist: the account list says 200 with nothing in it, the transfer log says 404.
#
# Usage:
# ./09.business_unit_accounts_GET.sh [BU]
#
#   BU  the business unit (default example_use_bu1)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/01.accounts_GET.sh, with the businessUnit filter, and from Admin/API 2.0/bash/16.TransferLogs/01.logs_transfers_GET.sh for the unit filter of the log.
# - There is no usage report per business unit: generateReport and activeUsers take no business unit (see the README). What the API gives per unit is the list of its accounts here, and the transfer log with businessUnit= in 10.
# - A unit that has child units: whether its list and its log hold the accounts and transfers of its children was not tried.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./09.business_unit_accounts_GET.sh [BU]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: BU.\n%s\n" "$#" "${USAGE}"; exit 2; fi
BU="${1:-${BU1}}"
uc_check_bu "${BU}" "${USAGE}"
st_session

uc_get accounts "businessUnit=${BU}" "limit=1000" "fields=name,businessUnit,homeFolder"
if [ "${LIST_CODE}" != "200" ]; then printf "GET /accounts?businessUnit=%s: HTTP %s: %s\n" "${BU}" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
TOTAL=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount')
echo "The business unit ${BU} has ${TOTAL} accounts:"
printf '%s' "${LIST_BODY}" | jq -r '.result[] | "  \(.name)  businessUnit \(.businessUnit)  home \(.homeFolder)"'

uc_get logs/transfers "businessUnit=${BU}" "limit=1" "fields=id"
case "${LIST_CODE}" in
    200) printf "The transfer log knows the unit: %s transfers in all, for every account that is in it now.\n" "$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount')" ;;
    404) printf "The transfer log does not know a business unit %s: HTTP 404, %s\n" "${BU}" "$(uc_why | head -1)" ;;
    *) printf "GET /logs/transfers?businessUnit=%s: HTTP %s: %s\n" "${BU}" "${LIST_CODE}" "$(uc_why)"; exit 1 ;;
esac
if [ "${TOTAL}" = "0" ]; then
    echo "No account answered. For a unit that does not exist the account list is a 200 with nothing in it, not a 404: an empty answer does not prove that the unit is there."
fi
