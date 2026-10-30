#!/bin/bash
# ==============================================================================
# Script Name: 06.filters_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 6: filters, paging and fields together, on the business units that 05 made. A filter (name=example_lst_*) changes totalCount: it counts what matches, not what the resource holds. The same call with limit,
# offset and fields= gives one page of names. A filter that matches nothing is an empty list, not an error.
#
# Usage:
# ./06.filters_GET.sh [PAGE_SIZE]
#
#   PAGE_SIZE  entries per page for the paged call, 1 or more (default 2)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/12.BusinessUnits/02.businessUnits_GET.sh.
# - The filter name takes * as a wildcard, and it does not care about upper and lower case. The filters of the other resources are in their own examples; earlier work found a few where totalCount ignores the filter, so check the resource you use.
# - It needs the units of 05: with none, it says so and exits 1.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./06.filters_GET.sh [PAGE_SIZE]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: PAGE_SIZE.\n%s\n" "$#" "${USAGE}"; exit 2; fi
PAGE_SIZE="${1:-2}"
uc_check_number "${PAGE_SIZE}" PAGE_SIZE "${USAGE}"
st_session

# uc_total_of QUERY...: the totalCount of a businessUnits list with that query, and the HTTP code in LIST_CODE
uc_total_of() {
    uc_list "businessUnits" "$@" "limit=1"
    [ "${LIST_CODE}" = "200" ] || { echo "GET /businessUnits ($*): HTTP ${LIST_CODE}"; uc_why; exit 1; }
    printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount'
}
PATTERN="${PREFIX}_*"
MATCHING=$(uc_total_of "name=${PATTERN}")
echo "name=${PATTERN}: totalCount ${MATCHING}"
if [ "${MATCHING}" = "0" ]; then
    echo "There is no business unit named ${PATTERN}. Run 05.location_POST.sh first."
    exit 1
fi
ALL=$(uc_total_of)
echo "No filter: totalCount ${ALL}. The filter made it ${MATCHING}: totalCount counts what matches."

uc_list "businessUnits" "name=${PATTERN}" "limit=${PAGE_SIZE}" "offset=${PAGE_SIZE}" "fields=name"
echo "name=${PATTERN}, limit=${PAGE_SIZE}, offset=${PAGE_SIZE}, fields=name: HTTP ${LIST_CODE}"
[ "${LIST_CODE}" = "200" ] || { uc_why; exit 1; }
echo "  returnCount $(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.returnCount') of totalCount $(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount'): $(printf '%s' "${LIST_BODY}" | jq -r '[.result[].name] | join(", ")')"

NOTHING=$(uc_total_of "name=${PREFIX}_nothing_*")
echo "name=${PREFIX}_nothing_*: HTTP ${LIST_CODE}, totalCount ${NOTHING}: a filter that finds nothing is an empty list, not an error."
[ "${NOTHING}" = "0" ] || exit 1

UPPER=$(uc_total_of "name=$(printf '%s' "${PATTERN}" | tr 'a-z' 'A-Z')")
echo "The pattern in capitals: totalCount ${UPPER}: upper and lower case are the same."
