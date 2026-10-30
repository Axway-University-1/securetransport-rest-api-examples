#!/bin/bash
# ==============================================================================
# Script Name: 02.files_GET_list.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 2: the list of a folder. GET /files/FOLDER answers an object, {files: [...], self: {...}} (a folder below the home adds parent), with no count. Without a limit it returns every entry, with no cap. limit and offset page it, and the only
# way to know that you have read the last page is that it is shorter than the limit. The script walks the folder that way, shows that limit=0 returns nothing, sorts with sortBy and order, and shows two limits the server
# cannot use.
#
# Usage:
# ./02.files_GET_list.sh [LIMIT]
#
#   LIMIT  entries per page for the walk, 1 or more (default 3)
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/01.files_GET.sh and 09.files_GET_query.sh.
# - limit=0 is the default page on the Admin API and on /transfers. Here it returns no entry at all: a client that uses 0 for "no limit" reads an empty folder.
# - sortBy takes fileName, lastModifiedTime or size, and order takes ASC or DESC (tried here: fileName, DESC and ASC).
# - limit=abc is answered 404 "HTTP 404 Not Found", not 400, and limit=-1 is not refused: it returns everything. Do not send a limit you did not check yourself. These two are what the server does on the release this was written on, and are shown, not asserted.
# - The folder must be there: run 01.files_POST_location.sh first.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./02.files_GET_list.sh [LIMIT]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: LIMIT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
LIMIT="${1:-3}"
eu_check_number "${LIMIT}" LIMIT "${USAGE}"
st_session

FOLDER_PATH="files/$(st_enc "${FOLDER}")"
eu_get "${FOLDER_PATH}"
echo "GET /${FOLDER_PATH}: HTTP ${EU_CODE}"
if [ "${EU_CODE}" != "200" ]; then
    eu_why
    [ "${EU_CODE}" != "404" ] || echo "There is no folder ${FOLDER}. Run 01.files_POST_location.sh first."
    exit 1
fi
if ! printf '%s' "${EU_BODY}" | jq -e '(.files | type == "array") and (.self | type == "object")' > /dev/null 2>&1; then
    echo "The answer has no files and self: it is not the list of a folder."
    exit 1
fi
TOTAL=$(printf '%s' "${EU_BODY}" | jq -r '.files | length')
echo "The answer is an object with $(printf '%s' "${EU_BODY}" | jq -r 'keys | join(", ")'): no count. With no limit it holds all ${TOTAL} entries."

OFFSET=0
READ=0
PAGES=0
while :; do
    eu_get "${FOLDER_PATH}" "limit=${LIMIT}" "offset=${OFFSET}"
    if [ "${EU_CODE}" != "200" ]; then
        echo "GET /${FOLDER_PATH} with limit=${LIMIT} and offset=${OFFSET}: HTTP ${EU_CODE}"
        eu_why
        exit 1
    fi
    GOT=$(printf '%s' "${EU_BODY}" | jq -r '.files | length')
    PAGES=$((PAGES + 1))
    printf '  page %s: offset %s, %s entries\n' "${PAGES}" "${OFFSET}" "${GOT}"
    READ=$((READ + GOT))
    OFFSET=$((OFFSET + GOT))
    [ "${GOT}" -ge "${LIMIT}" ] || break
    if [ "${PAGES}" -ge 1000 ]; then
        echo "Stopped after 1000 pages. Use a bigger LIMIT."
        exit 1
    fi
done
echo "Read ${READ} entries in ${PAGES} pages, the last one shorter than ${LIMIT}: that is the only sign of the end."
if [ "${READ}" -ne "${TOTAL}" ]; then
    echo "The pages held ${READ} entries and the unpaged answer ${TOTAL}: the folder changed while it was read."
    exit 1
fi

eu_get "${FOLDER_PATH}" "limit=0"
echo "limit=0: HTTP ${EU_CODE}, $(printf '%s' "${EU_BODY}" | jq -r '.files | length' 2>/dev/null) entries. Not the default page and not all: none."
[ "${EU_CODE}" = "200" ] || exit 1

for order in DESC ASC; do
    eu_get "${FOLDER_PATH}" "sortBy=fileName" "order=${order}"
    echo "sortBy=fileName&order=${order}: HTTP ${EU_CODE}, first $(printf '%s' "${EU_BODY}" | jq -r '.files[0].fileName // "-"'), last $(printf '%s' "${EU_BODY}" | jq -r '.files[-1].fileName // "-"')"
    [ "${EU_CODE}" = "200" ] || { eu_why; exit 1; }
done

for odd in abc -1; do
    eu_get "${FOLDER_PATH}" "limit=${odd}"
    echo "limit=${odd}: HTTP ${EU_CODE}$(printf '%s' "${EU_BODY}" | jq -r 'if (.files | type) == "array" then ", \(.files | length) entries" else ", " + (.message // "") end' 2>/dev/null)"
done
