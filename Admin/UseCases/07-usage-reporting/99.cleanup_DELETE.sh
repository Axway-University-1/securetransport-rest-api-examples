#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Removes what this use case made: the six accounts example_use_a1 to example_use_f1 (their home folders are emptied first, through the End User API), then the three business units
# example_use_bu1 to example_use_bu3, the state files and the administrator's session. It can be run twice.
#
# Usage:
# ./99.cleanup_DELETE.sh
#
# Risk: write
#
# Notes:
# - Written for this use case. The objects are removed by their exact names and nothing else is touched.
# - The accounts go before the units: a unit that still has an account is not deleted.
# - The transfers that 07 made STAY in the transfer log: no API call deletes a log entry. A log entry of a deleted account is still found with account=, and a deleted unit is no longer found with businessUnit=.
# - A name that is not there is 404 and is reported as not there. Any other answer is reported, and the script exits 1 at the end.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./99.cleanup_DELETE.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

STATUS=0
remove() {      # RESOURCE NAME LABEL
    local code
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/$1/$2" -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
    case "${code}" in
        204) echo "The $3 $2 was deleted." ;;
        404) ;;
        *) echo "The $3 $2 could not be deleted (HTTP ${code}): delete it by hand."; STATUS=1 ;;
    esac
}

for LINE in "${UC_ACCOUNTS[@]}"; do
    NAME="${LINE%% *}"
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ST_URL}/accounts/${NAME}" -H "accept: */*" -H "Referer: ${REFERER}")
    if [ "${code}" = "200" ] && [ -s "${PASSWORD_FILE}" ]; then
        uc_empty_home "${NAME}" "$(cat "${PASSWORD_FILE}")"
    fi
    remove accounts "${NAME}" account
done
for NAME in "${UC_BUS[@]}"; do
    remove businessUnits "${NAME}" "business unit"
done

if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
fi
rm -f "${JAR}" "${CSRF_FILE}" "${PASSWORD_FILE}" "${WINDOW_FILE}" "${REPORT_FILE}"
echo "Cleaned up. The transfers stay in the transfer log."
exit ${STATUS}
