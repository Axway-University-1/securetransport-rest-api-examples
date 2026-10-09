#!/bin/bash
# ==============================================================================
# Script Name: 01.userClasses_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves user classes using the `/userClasses` endpoint.
# It demonstrates:
# - The number of classes on the server
# - The classes matching a name, in the order the server tries them, one line each
# - Only the enabled ones
#
# Usage:
# ./01.userClasses_GET.sh [NAME [USER_TYPE]]
#
#   NAME       list only the classes with this name; takes a * wildcard (default *)
#   USER_TYPE  any (default), real, virtual or * : only the classes of that type. The * is the type of a class that
#              fits both, not a wildcard, so quote it
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A user class decides which class an account is in when it logs in. The server tries the classes in `order` and the
#   FIRST enabled one that matches wins; a class matches when its userType, userName, group and address fit the login
#   and its expression (when there is one) is true. The lab has two classes of its own, VirtClass (virtual) and RealClass
#   (real), that match every login of their type: never change or delete them.
# - Confirmed directly: the answer is `{resultSet, result}`, and the list is NOT in the order of the classes: sort by `order`
#   yourself, as this script does. `className=` ignores case and takes a `*` (`EXAMPLE_F*` finds `example_f1`). The other filters
#   are exact and take no wildcard: `userType=` (real, virtual or the `*` type; another text finds nothing), `userName=nobody*`
#   finds nothing when no class has that very text, `group=`, `address=`, `expression=`, `order=`. `enabled=` takes true or false
#   and any other text means false. `limit=0` is the default page of 100, not all (the reference: it means Webservices.EntriesPerPage), so this script asks for `limit=1000`, a negative `limit` is 400 "The limit should be a positive number or 0.",
#   `limit=abc` and a negative `offset` are 400. `fields=` keeps the keys named, an unknown one is 400 "Field nope does not exist.".
# - A class has an `id`; the other examples in this folder look it up by name.
# - Requires `jq`, which prints one line per class.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when USER_TYPE is wrong or there are more than two arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/userClasses"
PATTERN="${1:-*}"
USER_TYPE="${2:-any}"
if [ "$#" -gt 2 ]; then
    printf "Usage: ./01.userClasses_GET.sh [NAME [USER_TYPE]]\n"
    exit 2
fi
case "${USER_TYPE}" in
    any|real|virtual|'*') ;;
    *) printf "USER_TYPE is any, real, virtual or *, not %s.\n" "${USER_TYPE}"; exit 2 ;;
esac

TYPE_FILTER=()
[ "${USER_TYPE}" != "any" ] && TYPE_FILTER=(--data-urlencode "userType=${USER_TYPE}")

LINE='"  \(.order)  \(.className)  \(.userType)  user \(.userName)  group \(.group)  address \(.address)  \(if .enabled then "enabled" else "disabled" end)  expression \(if .expression == "" then "-" else .expression end)"'

# st_get CURL_ARGUMENTS...: a GET of the URL given (with any curl options, such as -G --data-urlencode ...). The answer
# is left in RESPONSE. A status other than 200 ends the script with exit 1, after printing the status and the answer.
st_get() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "$@" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}

printf "User classes on the server: "
st_get "${MAIN_URL}?limit=1&fields=id"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

printf "\nThe classes matching %s, in the order they are tried: order, name, type, user, group, address, state, expression:\n" "${PATTERN}"
st_get -G "${MAIN_URL}" "${TYPE_FILTER[@]}" --data-urlencode "className=${PATTERN}" --data-urlencode "limit=1000"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // []) | sort_by(.order)[] | ${LINE}"

printf "\nOnly the enabled ones:\n"
st_get -G "${MAIN_URL}" "${TYPE_FILTER[@]}" --data-urlencode "className=${PATTERN}" --data-urlencode "limit=1000" --data-urlencode "enabled=true"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // []) | sort_by(.order)[] | ${LINE}"
