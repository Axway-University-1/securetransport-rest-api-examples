#!/bin/bash
# ==============================================================================
# Script Name: 04.head_exists.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 4: does it exist? HEAD /RESOURCE/NAME has no body, and the code is the answer: 200 it is there, 404 it is not. The script asks for an object the list has and for one that it has not, and then for a
# resource that has no HEAD at all (a 405 is not "not there").
#
# Usage:
# ./04.head_exists.sh [RESOURCE] [NAME]
#
#   RESOURCE  the resource to ask (default accounts)
#   NAME      the object to ask for (default: the first one the list gives)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/03.accounts_name_HEAD.sh.
# - The object that is not there is NAME with _example_missing after it. If the server says anything but 200 and 404, the script says what it got and exits 1.
# - deniedUsers answers 405 to a HEAD (and to a GET) of one name: the resource has no read of one object. Look at the code and do not take a 405 for "not there".
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./04.head_exists.sh [RESOURCE] [NAME]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: RESOURCE and NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
RESOURCE="${1:-accounts}"
NAME="${2:-}"
uc_check_resource "${RESOURCE}" "${USAGE}"
st_session

if [ -z "${NAME}" ]; then
    uc_list "${RESOURCE}" "limit=1" "fields=name"
    [ "${LIST_CODE}" = "200" ] || { echo "GET /${RESOURCE}?limit=1: HTTP ${LIST_CODE}"; uc_why; exit 1; }
    NAME=$(printf '%s' "${LIST_BODY}" | jq -r '.result[0].name // empty')
    [ -n "${NAME}" ] || { echo "The list /${RESOURCE} has no entry with a name to ask for. Give NAME."; exit 1; }
fi

# uc_head PATH: the status code of a HEAD of the path
uc_head() {
    curl -k -s -o /dev/null -w "%{http_code}" --head -b "${JAR}" "${ST_URL}/$1" -H "accept: */*" -H "Referer: ${REFERER}"
}
STATUS=0
THERE=$(uc_head "${RESOURCE}/$(printf '%s' "${NAME}" | jq -Rr @uri)")
echo "HEAD /${RESOURCE}/${NAME}: ${THERE}"
if [ "${THERE}" = "200" ]; then echo "  200: it is there."; else echo "  An object the list gave should be 200."; STATUS=1; fi
MISSING="${NAME}_example_missing"
GONE=$(uc_head "${RESOURCE}/$(printf '%s' "${MISSING}" | jq -Rr @uri)")
echo "HEAD /${RESOURCE}/${MISSING}: ${GONE}"
if [ "${GONE}" = "404" ]; then echo "  404: it is not there."; else echo "  A name that is not there should be 404."; STATUS=1; fi
NONE=$(uc_head "deniedUsers/example_lst_none")
echo "HEAD /deniedUsers/example_lst_none: ${NONE}"
if [ "${NONE}" = "405" ]; then echo "  405: this resource has no HEAD of one name. It does not say 'not there'."; else echo "  (deniedUsers answered ${NONE}; it answered 405 on the lab this was written on.)"; fi
exit ${STATUS}
