#!/bin/bash
# ==============================================================================
# Script Name: 06.counting_without_totalCount.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 6: counting a list that has no totalCount. The folder list and /transfers say nothing about how many entries there are, so the count is what you read: ask for a page, add the entries, and stop at the first page
# shorter than the limit. The script counts the files of the folder and the transfers that way, and checks the folder count against the unpaged answer.
#
# Usage:
# ./06.counting_without_totalCount.sh [PAGE_SIZE]
#
#   PAGE_SIZE  entries per call, 1 or more (default 100)
#
# Risk: read
#
# Notes:
# - Written for this use case.
# - The walk is the one of 02, with a stop on a page shorter than PAGE_SIZE: a list that is an exact multiple of PAGE_SIZE costs one more call, which returns nothing.
# - The transfers are counted only for an account that may use the transfers web service; for the others the script says so and counts the files alone.
# - Counting transfers by reading them is slow when there are many. Counting a long history is a job for the Admin API (logs/transfers has a totalCount), not for an end user.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./06.counting_without_totalCount.sh [PAGE_SIZE]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: PAGE_SIZE.\n%s\n" "$#" "${USAGE}"; exit 2; fi
PAGE_SIZE="${1:-100}"
eu_check_number "${PAGE_SIZE}" PAGE_SIZE "${USAGE}"
st_session

# eu_walk PATH FILTER: counts the entries of /PATH by reading pages of PAGE_SIZE; FILTER is the jq expression for the entries of one answer. Sets WALK_COUNT and WALK_PAGES, WALK_CODE for a refusal.
eu_walk() {
    local path="$1" filter="$2" offset=0 got
    WALK_COUNT=0
    WALK_PAGES=0
    WALK_CODE=200
    while :; do
        eu_get "${path}" "limit=${PAGE_SIZE}" "offset=${offset}"
        if [ "${EU_CODE}" != "200" ]; then WALK_CODE="${EU_CODE}"; return; fi
        got=$(printf '%s' "${EU_BODY}" | jq -r "${filter} | length")
        WALK_PAGES=$((WALK_PAGES + 1))
        WALK_COUNT=$((WALK_COUNT + got))
        offset=$((offset + got))
        [ "${got}" -ge "${PAGE_SIZE}" ] || return
        if [ "${WALK_PAGES}" -ge 1000 ]; then WALK_CODE=1000; return; fi
    done
}

FOLDER_PATH="files/$(st_enc "${FOLDER}")"
eu_get "${FOLDER_PATH}"
[ "${EU_CODE}" = "200" ] || { echo "GET /${FOLDER_PATH}: HTTP ${EU_CODE}"; eu_why; exit 1; }
UNPAGED=$(printf '%s' "${EU_BODY}" | jq -r '.files | length')
eu_walk "${FOLDER_PATH}" ".files"
[ "${WALK_CODE}" = "200" ] || { echo "Counting the files stopped (HTTP ${WALK_CODE}) after ${WALK_PAGES} pages."; exit 1; }
echo "Files in ${FOLDER}: ${WALK_COUNT}, counted in ${WALK_PAGES} calls of up to ${PAGE_SIZE}."
if [ "${WALK_COUNT}" -ne "${UNPAGED}" ]; then
    echo "The unpaged answer has ${UNPAGED} entries: the folder changed while it was counted."
    exit 1
fi

eu_get "transfers" "limit=1"
if [ "${EU_CODE}" = "403" ]; then
    echo "Transfers are not counted:"
    eu_not_allowed
    exit 0
fi
[ "${EU_CODE}" = "200" ] || { echo "GET /transfers: HTTP ${EU_CODE}"; eu_why; exit 1; }
eu_walk "transfers" "."
[ "${WALK_CODE}" = "200" ] || { echo "Counting the transfers stopped (HTTP ${WALK_CODE}) after ${WALK_PAGES} pages."; exit 1; }
echo "Transfers: ${WALK_COUNT}, counted in ${WALK_PAGES} calls of up to ${PAGE_SIZE}."
if [ "${PAGE_SIZE}" -le 100 ] && [ "${WALK_COUNT}" -ge 100 ]; then
    echo "That is more than the 100 of the default page: a client that read one call would have missed $((WALK_COUNT - 100))."
fi
