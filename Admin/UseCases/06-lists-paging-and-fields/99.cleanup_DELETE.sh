#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Removes what this use case made: the business units example_lst_1 to example_lst_9 that are still there, the state files and the administrator's session. It can be run twice.
#
# Usage:
# ./99.cleanup_DELETE.sh
#
# Risk: write
#
# Notes:
# - Written for this use case. The units are removed by their exact names and nothing else is touched.
# - A unit that is not there is 404 and is reported as not there. Any other answer is reported, and the script exits 1 at the end.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./99.cleanup_DELETE.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

STATUS=0
for n in $(seq 1 "${MAX_OBJECTS}"); do
    NAME=$(uc_name "${n}")
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/businessUnits/${NAME}" -H "accept: application/json" -H "Referer: ${REFERER}" \
           -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
    case "${code}" in
        204) echo "The business unit ${NAME} was deleted." ;;
        404) ;;
        *) echo "The business unit ${NAME} could not be deleted (HTTP ${code}): delete it by hand."; STATUS=1 ;;
    esac
done

if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
fi
rm -f "${JAR}" "${CSRF_FILE}"
echo "Cleaned up."
exit ${STATUS}
