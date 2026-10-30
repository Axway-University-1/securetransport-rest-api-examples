#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Puts everything back: the option of step 11 (from state.local.option.json, if that file is still there), then deletes the route and the account of this use case if they are still there, and the files of this folder that hold
# state, and ends the administrator's session. It can be run twice.
#
# Usage:
# ./99.cleanup_DELETE.sh [NAME]
#
#   NAME  the account (and NAME_route, the route) to remove (default example_chg)
#
# Risk: write
#
# Notes:
# - Written for this use case. The objects are removed by their exact name, which must start with example_.
# - The option is put back first: it is the only thing here that is not ours. When it cannot be put back the script says so, keeps the copy, and exits 1.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./99.cleanup_DELETE.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"

STATUS=0
if [ -s "${OPTION_FILE}" ]; then
    OPTION=$(jq -r .name "${OPTION_FILE}")
    code=$(uc_option_put "${OPTION}" "$(jq -c .values "${OPTION_FILE}")")
    if [ "${code}" = "204" ]; then
        echo "The option ${OPTION} was put back as saved: $(jq -c .values "${OPTION_FILE}")."
        rm -f "${OPTION_FILE}"
    else
        echo "The option ${OPTION} could not be put back (HTTP ${code}). The copy stays in $(basename "${OPTION_FILE}"): set it by hand to $(jq -c .values "${OPTION_FILE}")."
        STATUS=1
    fi
fi

ROUTE_ID=$(uc_route_id)
if [ -n "${ROUTE_ID}" ]; then
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ST_URL}/routes/${ROUTE_ID}" -H "accept: */*" -H "Referer: ${REFERER}")
else
    code=404
fi
if [ "${code}" = "200" ]; then
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/routes/${ROUTE_ID}" -H "accept: application/json" -H "Referer: ${REFERER}" \
           -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
    if [ "${code}" = "204" ]; then
        echo "The route ${ROUTE_NAME} was deleted."
    else
        echo "The route ${ROUTE_NAME} could not be deleted (HTTP ${code}): delete it by hand."
        STATUS=1
    fi
elif [ "${code}" = "404" ]; then
    echo "There is no route ${ROUTE_NAME}: nothing to delete."
fi

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ACCOUNT_URL}" -H "accept: */*" -H "Referer: ${REFERER}")
if [ "${code}" = "200" ]; then
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ACCOUNT_URL}" -H "accept: application/json" -H "Referer: ${REFERER}" \
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
rm -f "${JAR}" "${CSRF_FILE}" "${ROUTE_ID_FILE}" "${ACCOUNT_COPY}" "${ROUTE_COPY}"
echo "Cleaned up."
exit ${STATUS}
