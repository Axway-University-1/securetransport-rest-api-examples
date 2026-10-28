#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-28
# Location: Sofia
# ==============================================================================
# Description:
# Removes what this use case made: the account, if it is still there (its home is emptied first, when the password is known), the files of this folder that hold state, and the administrator's session.
# It can be run twice.
#
# Usage:
# ./99.cleanup_DELETE.sh [NAME]
#
#   NAME  the account to remove (default example_onboard)
#
# Risk: write
#
# Notes:
# - Written for this use case. The account is removed by its exact name, which must start with example_.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./99.cleanup_DELETE.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"

STATUS=0
NAME_URI=$(printf '%s' "${NAME}" | jq -Rr @uri)
st_session
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ST_URL}/accounts/${NAME_URI}" -H "accept: */*" -H "Referer: ${REFERER}")
if [ "${code}" = "200" ]; then
    if [ -s "${PASSWORD_FILE}" ]; then
        uc_empty_home "${NAME}" "$(cat "${PASSWORD_FILE}")"
    fi
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/accounts/${NAME_URI}" -H "accept: application/json" -H "Referer: ${REFERER}" \
           -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
    if [ "${code}" = "204" ]; then
        echo "The account ${NAME} was deleted."
    else
        echo "The account ${NAME} could not be deleted (HTTP ${code}): delete it by hand."
        STATUS=1
    fi
elif [ "${code}" = "404" ]; then
    echo "There is no account ${NAME}: nothing to delete."
fi

if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
fi
rm -f "${JAR}" "${CSRF_FILE}" "${PASSWORD_FILE}"
echo "Cleaned up."
exit ${STATUS}
