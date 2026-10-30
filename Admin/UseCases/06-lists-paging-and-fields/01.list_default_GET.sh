#!/bin/bash
# ==============================================================================
# Script Name: 01.list_default_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 1: what a list answers when you ask for nothing more. An Admin list is an object, {resultSet: {returnCount, totalCount}, result: [...]}. returnCount is the number of entries in this answer, totalCount the number of
# entries there are. Without a limit the answer is one page of 100 (the setting Webservices.EntriesPerPage), and the script shows what limit=0 and limit=1 do.
#
# Usage:
# ./01.list_default_GET.sh [RESOURCE]
#
#   RESOURCE  the list to read (default accounts), for example servers or logs/transfers
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/01.accounts_GET.sh. The setting is read as in 13.Configurations.
# - limit=0 is the default page, not "all". limit=1 is the way to count: one entry comes back and totalCount says how many there are.
# - A resource whose answer has no resultSet is not a list: the script says so and exits 1.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./01.list_default_GET.sh [RESOURCE]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: RESOURCE.\n%s\n" "$#" "${USAGE}"; exit 2; fi
RESOURCE="${1:-accounts}"
uc_check_resource "${RESOURCE}" "${USAGE}"
st_session

uc_list "${RESOURCE}"
echo "GET /${RESOURCE}: HTTP ${LIST_CODE}"
[ "${LIST_CODE}" = "200" ] || { uc_why; exit 1; }
if ! printf '%s' "${LIST_BODY}" | jq -e '.resultSet.totalCount != null and (.result | type == "array")' > /dev/null 2>&1; then
    echo "The answer has no resultSet and result: /${RESOURCE} is not an Admin list."
    exit 1
fi
RETURNED=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.returnCount')
TOTAL=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount')
echo "returnCount ${RETURNED}, totalCount ${TOTAL}."
if [ "${RETURNED}" -lt "${TOTAL}" ]; then
    echo "This is one page, the first ${RETURNED} of ${TOTAL}. 02.paging_walk.sh reads the rest."
else
    echo "The whole list came in this one answer."
fi

uc_list "configurations/options" "name=Webservices.EntriesPerPage"
if [ "${LIST_CODE}" = "200" ]; then
    echo "The page the server gives when you ask for no limit is Webservices.EntriesPerPage: $(printf '%s' "${LIST_BODY}" | jq -r '.result[0].values[0] // "not set"')."
else
    echo "Could not read Webservices.EntriesPerPage (HTTP ${LIST_CODE}). The default page is 100 unless an administrator changed it."
fi

uc_list "${RESOURCE}" "limit=0"
echo "limit=0: HTTP ${LIST_CODE}"
[ "${LIST_CODE}" = "200" ] || { uc_why; exit 1; }
echo "  returnCount $(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.returnCount'): the same default page. limit=0 does not mean all."

uc_list "${RESOURCE}" "limit=1"
echo "limit=1: HTTP ${LIST_CODE}"
[ "${LIST_CODE}" = "200" ] || { uc_why; exit 1; }
echo "  returnCount $(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.returnCount'), totalCount $(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount'): to count a list, ask for one entry and read totalCount, not returnCount."
