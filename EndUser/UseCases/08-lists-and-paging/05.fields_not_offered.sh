#!/bin/bash
# ==============================================================================
# Script Name: 05.fields_not_offered.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 5: there is no fields= on the End User API. The Admin API narrows an answer with fields=name. Here the same parameter is not refused and has no effect: the answer is whole. The script asks for fields=fileName on the
# folder list, fields=name on /myself and fields=filename on /transfers, and counts the fields of the first entry with and without it. Do not use fields= to make an answer small.
#
# Usage:
# ./05.fields_not_offered.sh
#
# Risk: read
#
# Notes:
# - Written for this use case. The Admin API's fields= is in Admin/UseCases/06-lists-paging-and-fields, step 03.
# - If an answer is narrower with fields= than without, this release offers it: the script says so and exits 1, because the use case and its README are then out of date.
# - /transfers is skipped, with the reason, for an account that may not use the transfers web service.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./05.fields_not_offered.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

# eu_fields_of FILTER: the number of fields of the first entry, with the jq FILTER that finds the entry
eu_fields_of() { printf '%s' "${EU_BODY}" | jq -r "(${1}) | if type == \"object\" then keys | length else 0 end" 2>/dev/null; }
STATUS=0
# eu_compare PATH FIELD ENTRY: the first entry of /PATH with and without fields=FIELD
eu_compare() {
    local path="$1" field="$2" entry="$3" whole narrow
    eu_get "${path}"
    [ "${EU_CODE}" = "200" ] || { echo "GET /${path}: HTTP ${EU_CODE}"; eu_why; STATUS=1; return; }
    whole=$(eu_fields_of "${entry}")
    eu_get "${path}" "fields=${field}"
    echo "GET /${path}?fields=${field}: HTTP ${EU_CODE}"
    [ "${EU_CODE}" = "200" ] || { eu_why; STATUS=1; return; }
    narrow=$(eu_fields_of "${entry}")
    echo "  the first entry has ${whole} fields, and ${narrow} with fields=${field}."
    if [ "${whole}" = "${narrow}" ]; then echo "  fields= made no difference."; else echo "  fields= changed the answer: this release offers it. This use case is out of date."; STATUS=1; fi
}

eu_compare "files/$(st_enc "${FOLDER}")" "fileName" ".files[0]"
eu_compare "myself" "name" "."
eu_get "transfers" "limit=1"
if [ "${EU_CODE}" = "403" ]; then
    echo "GET /transfers is skipped:"
    eu_not_allowed
else
    eu_compare "transfers" "filename" ".[0]"
fi
echo "Ask for the fields you need and read those, but expect the whole entry, whatever fields= says."
exit ${STATUS}
