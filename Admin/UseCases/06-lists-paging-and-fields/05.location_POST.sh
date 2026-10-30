#!/bin/bash
# ==============================================================================
# Script Name: 05.location_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 5: a new object and the Location header. A POST that creates answers 201 with no body: the address of the new object is in the Location header. The script makes COUNT throwaway business units
# (example_lst_1, example_lst_2, ...), prints the Location of each, reads the first one back by that address, and shows what a second POST of the same name answers. The units are what 06 filters and pages through.
#
# Usage:
# ./05.location_POST.sh [COUNT]
#
#   COUNT  how many business units to make, 1 to 9 (default 5)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/12.BusinessUnits/01.businessUnits_POST.sh (a name and a base folder /home/NAME; the unit makes no folder).
# - The Location of a business unit ends with its name. For some objects the last part is an id (a route), not a name: read it from the header, do not build it.
# - A name that is taken is refused with 400 and nothing is changed. A unit that is already there from an earlier run stops the script at its first POST: run 99.cleanup_DELETE.sh.
# - 99.cleanup_DELETE.sh removes example_lst_1 to example_lst_9 by name.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./05.location_POST.sh [COUNT]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: COUNT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
COUNT="${1:-5}"
if [[ ! "${COUNT}" =~ ^[1-9]$ ]]; then
    printf "COUNT is '%s': it must be a whole number from 1 to %s.\n%s\n" "${COUNT}" "${MAX_OBJECTS}" "${USAGE}"
    exit 2
fi
st_session

HEADERS=$(mktemp)
ANSWER=$(mktemp)
trap 'rm -f "${HEADERS}" "${ANSWER}"' EXIT
# uc_post_unit NAME: POSTs the business unit; leaves the status in POST_CODE and the headers and the body in the temporary files
uc_post_unit() {
    local body
    body=$(jq -cn --arg name "$1" '{name: $name, baseFolder: ("/home/" + $name)}')
    POST_CODE=$(curl -k -s -o "${ANSWER}" -w "%{http_code}" -D "${HEADERS}" -b "${JAR}" -X POST "${ST_URL}/businessUnits" -H "accept: */*" -H "Referer: ${REFERER}" \
                -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "${body}")
}
FIRST_LOCATION=""
for n in $(seq 1 "${COUNT}"); do
    NAME=$(uc_name "${n}")
    uc_post_unit "${NAME}"
    echo "POST /businessUnits ${NAME}: HTTP ${POST_CODE}"
    if [ "${POST_CODE}" != "201" ]; then
        jq -r '(.validationErrors // [.message // empty])[]' "${ANSWER}" 2>/dev/null || cat "${ANSWER}"
        echo "Nothing more was made. If ${NAME} is left from an earlier run, remove it with 99.cleanup_DELETE.sh."
        exit 1
    fi
    LOCATION=$(tr -d '\r' < "${HEADERS}" | sed -n 's/^[Ll]ocation: *//p')
    echo "  Location: ${LOCATION}"
    [ "${n}" -ne 1 ] || { FIRST_LOCATION="${LOCATION}"; echo "  Body: $(wc -c < "${ANSWER}" | tr -d ' ') bytes. A 201 has no body; the address is the answer."; }
    case "${LOCATION}" in
        */businessUnits/"${NAME}") ;;
        *) echo "  The Location does not end with /businessUnits/${NAME}."; exit 1 ;;
    esac
done

code=$(curl -k -s -o "${ANSWER}" -w "%{http_code}" -b "${JAR}" "${FIRST_LOCATION}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "GET of that address: HTTP ${code}, the unit is $(jq -r '.name // "?"' "${ANSWER}" 2>/dev/null)."
[ "${code}" = "200" ] || exit 1

NAME=$(uc_name 1)
uc_post_unit "${NAME}"
echo "The same POST again (${NAME}): HTTP ${POST_CODE}"
if [ "${POST_CODE}" = "201" ]; then
    echo "The server made a second unit of the same name. It was expected to refuse."
    exit 1
fi
jq -r '(.validationErrors // [.message // empty])[]' "${ANSWER}" 2>/dev/null | sed 's/^/  /'
