#!/bin/bash
# ==============================================================================
# Script Name: 02.paging_walk.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 2: reads a whole list, one page after another. Each call asks for limit=PAGE_SIZE and an offset (the number of entries to skip), and the loop stops when it has read as many entries as totalCount says.
# At the end it asks for a page past the end, and compares what it read with totalCount.
#
# Usage:
# ./02.paging_walk.sh [RESOURCE] [PAGE_SIZE]
#
#   RESOURCE   the list to read (default accounts)
#   PAGE_SIZE  entries per call, 1 or more (default 5). For a long list such as logs/transfers use a few hundred: 1000 took about 4 seconds, 5000 about 15.
#
# Risk: read
#
# Notes:
# - Written for this use case; the same loop is in Features/Guidance (Lists: counts and pages).
# - The loop advances by the number of entries it got and stops at totalCount, so a list whose size is a multiple of PAGE_SIZE costs no empty last call. It also stops on an empty page, and after 1000 pages.
# - An offset past the end is not an error: 200, an empty result, and the same totalCount.
# - If the entries read are not totalCount, the list changed while it was read (an entry was added or removed): the script says so and exits 1. A resource with a sort parameter (the transfer log has sortByStartTime) keeps the pages steady.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./02.paging_walk.sh [RESOURCE] [PAGE_SIZE]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: RESOURCE and PAGE_SIZE.\n%s\n" "$#" "${USAGE}"; exit 2; fi
RESOURCE="${1:-accounts}"
PAGE_SIZE="${2:-5}"
uc_check_resource "${RESOURCE}" "${USAGE}"
uc_check_number "${PAGE_SIZE}" PAGE_SIZE "${USAGE}"
st_session

OFFSET=0
READ=0
PAGES=0
TOTAL=""
while :; do
    uc_list "${RESOURCE}" "limit=${PAGE_SIZE}" "offset=${OFFSET}"
    if [ "${LIST_CODE}" != "200" ]; then
        echo "GET /${RESOURCE} with limit=${PAGE_SIZE} and offset=${OFFSET}: HTTP ${LIST_CODE}"
        uc_why
        exit 1
    fi
    GOT=$(printf '%s' "${LIST_BODY}" | jq -r '.result | length')
    [ -n "${TOTAL}" ] || TOTAL=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount')
    PAGES=$((PAGES + 1))
    printf '  page %s: offset %s, %s entries\n' "${PAGES}" "${OFFSET}" "${GOT}"
    READ=$((READ + GOT))
    OFFSET=$((OFFSET + GOT))
    [ "${GOT}" -gt 0 ] || break
    [ "${READ}" -lt "${TOTAL}" ] || break
    if [ "${PAGES}" -ge 1000 ]; then
        echo "Stopped after 1000 pages. Use a bigger PAGE_SIZE."
        exit 1
    fi
done
echo "Read ${READ} entries in ${PAGES} pages. totalCount said ${TOTAL}."

uc_list "${RESOURCE}" "limit=${PAGE_SIZE}" "offset=${TOTAL}"
echo "A page past the end (offset ${TOTAL}): HTTP ${LIST_CODE}, $(printf '%s' "${LIST_BODY}" | jq -r '.result | length') entries, totalCount $(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount')."
[ "${LIST_CODE}" = "200" ] || exit 1

if [ "${READ}" -ne "${TOTAL}" ]; then
    echo "The pages held ${READ} entries and totalCount said ${TOTAL}: the list changed while it was read. Read it again."
    exit 1
fi
