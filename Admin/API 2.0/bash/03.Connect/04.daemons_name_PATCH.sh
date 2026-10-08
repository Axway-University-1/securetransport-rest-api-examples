#!/bin/bash
# ==============================================================================
# Script Name: 04.daemons_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes one setting of a daemon, using the `/daemons/{name}` endpoint with PATCH: a JSON Patch
# document that replaces one field. Unlike PUT (03.daemons_name_PUT.sh) it sends only what changes.
# It demonstrates:
# - Patching `maxConnections` (a number), `preferBouncyCastleProvider` (a boolean) or `banner` (text), each typed correctly by jq
# - The old value is read and printed first, with the command that puts it back
# - The HTTP code, and an exit of 1 when the server refuses
#
# Usage:
# ./04.daemons_name_PATCH.sh NAME FIELD VALUE
#
#   NAME   the daemon: the API only accepts ssh (any other name is answered 400 by the server)
#   FIELD  maxConnections, preferBouncyCastleProvider or banner
#   VALUE  the new value: a whole number (the server accepts 1 to 100000), true or false, or any text ("" for no banner)
#
# Without all three arguments, or with a FIELD or VALUE that does not fit, the script prints this usage, sends NOTHING and exits 2.
#
# Risk: config - changes one setting of the SSH daemon; put it back afterwards (the script prints how)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This changes the configuration of the real daemon, so there is no default: the daemon, the field and the value are arguments. The script prints the old
#   value, and the command that puts it back, before it changes anything.
# - The reference says a changed configuration takes effect when the daemon restarts. This script does not restart it. An open connection is not dropped.
# - Requires `jq`, which reads the old value and builds the patch with the right type.
# - Confirmed directly: a success is 204 with no body. The endpoint only ever accepts the name `ssh`: GET, PUT and PATCH on `http`, `ftp`,
#   `pesit`, `as2`, `SSH` or any other name are 400 "Invalid value for parameter name, expected (ssh)". `maxConnections` must be 1 to 100000
#   (400 "Property 'maxConnections' should be in the range from 1 to 100000" for -10, 0 and 100001, 400 "Cannot parse 'abc' to int." for text);
#   `preferBouncyCastleProvider` must be a boolean (400 "Cannot parse 'yes' to boolean.").
#   PATCH `replace` works on each of the three fields (204), also with `maxConnections` sent as the text "7"; a path that does not exist is 400 `Missing field "nope"`.
# - Exit codes: 0 when the server answered 204, 1 when it refuses (or the daemon cannot be read), 2 when an argument is missing or wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons"
USAGE="Usage: 04.daemons_name_PATCH.sh NAME FIELD VALUE, with FIELD maxConnections, preferBouncyCastleProvider or banner"
NAME="$1"
FIELD="$2"
VALUE="$3"

if [ "$#" -ne 3 ]; then
    printf "This changes one setting of a daemon. Nothing was sent: it needs the daemon, the field and the value.\n"
    printf "%s\n" "${USAGE}"
    exit 2
fi
case "${NAME}" in
    ''|*[!A-Za-z0-9_-]*) printf "NAME is a daemon name such as ssh.\n%s\n" "${USAGE}"; exit 2 ;;
esac
case "${FIELD}" in
    maxConnections) KIND=number ;;
    preferBouncyCastleProvider) KIND=boolean ;;
    banner) KIND=string ;;
    *) printf "FIELD is maxConnections, preferBouncyCastleProvider or banner, not %s.\n%s\n" "${FIELD}" "${USAGE}"; exit 2 ;;
esac
if [ "${KIND}" = "number" ] && ! [[ "${VALUE}" =~ ^-?[0-9]{1,9}$ ]]; then
    printf "VALUE for maxConnections is a whole number, not %s.\n%s\n" "${VALUE}" "${USAGE}"
    exit 2
fi
if [ "${KIND}" = "boolean" ] && [ "${VALUE}" != "true" ] && [ "${VALUE}" != "false" ]; then
    printf "VALUE for preferBouncyCastleProvider is true or false, not %s.\n%s\n" "${VALUE}" "${USAGE}"
    exit 2
fi

NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')

printf "Reading the daemon %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${NAME_URI}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the daemon %s: HTTP %s\n" "${NAME}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
OLD_VALUE=$(printf '%s' "${RESPONSE}" | jq -r --arg field "${FIELD}" '.[$field] // "" | tostring')
printf "The %s of %s is now '%s'.\n" "${FIELD}" "${NAME}" "${OLD_VALUE}"
printf "To put it back: ./04.daemons_name_PATCH.sh %s %s %q\n" "${NAME}" "${FIELD}" "${OLD_VALUE}"

BODY=$(jq -cn --arg path "/${FIELD}" --arg value "${VALUE}" --arg kind "${KIND}" \
  '[{op: "replace", path: $path, value: (if $kind == "number" then ($value | tonumber) elif $kind == "boolean" then ($value == "true") else $value end)}]')

printf "Setting it to '%s'...\n" "${VALUE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${NAME_URI}" -H "accept: application/json" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf "Done. The daemon takes the new setting when it restarts.\n"
