#!/bin/bash
# ==============================================================================
# Script Name: 03.daemons_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces the configuration of a daemon, using the `/daemons/{name}` endpoint with PUT.
# It demonstrates:
# - A PUT sends the whole object: all three settings of the SSH daemon are given and all three are sent
# - The old settings are read and printed first, with the command that puts them back
# - The HTTP code, and an exit of 1 when the server refuses
#
# Usage:
# ./03.daemons_name_PUT.sh NAME MAX_CONNECTIONS PREFER_BOUNCY_CASTLE BANNER
#
#   NAME                  the daemon: the API only accepts ssh (any other name is answered 400 by the server)
#   MAX_CONNECTIONS       a whole number; the server accepts 1 to 100000
#   PREFER_BOUNCY_CASTLE  true or false
#   BANNER                the SSH welcome message; give "" for none. It is required: a PUT without it is refused
#
# Without all four arguments the script prints this usage, sends NOTHING and exits 2.
#
# Risk: config - changes the configuration of the SSH daemon; put it back afterwards (the script prints how)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This changes the configuration of the real daemon, so there is no default: every value is an argument. Put it back afterwards:
#   the script prints the old settings, and the command that restores them, before it changes anything.
# - A PUT replaces the whole object, so it needs all three settings. Confirmed directly: leaving out `banner`, or sending it as null, is not a 400 but a
#   bare 403 "The server was unable to comply with your request"; an empty banner is fine. `maxConnections` as the text "12" is accepted.
# - The reference says a changed configuration takes effect when the daemon restarts. This script does not restart it; the restart (05.daemons_operations_POST.sh)
#   is disruptive. An already open connection is not dropped by this call.
# - Requires `jq`, which reads the old settings and builds the request body.
# - Confirmed directly: a success is 204 with no body. The endpoint only ever accepts the name `ssh`: GET, PUT and PATCH on `http`, `ftp`,
#   `pesit`, `as2`, `SSH` or any other name are 400 "Invalid value for parameter name, expected (ssh)". `maxConnections` must be 1 to 100000
#   (400 "Property 'maxConnections' should be in the range from 1 to 100000" for -10, 0 and 100001, 400 "Cannot parse 'abc' to int." for text);
#   `preferBouncyCastleProvider` must be a boolean (400 "Cannot parse 'yes' to boolean.").
# - Exit codes: 0 when the server answered 204, 1 when it refuses (or the daemon cannot be read), 2 when an argument is missing or wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons"
USAGE="Usage: 03.daemons_name_PUT.sh NAME MAX_CONNECTIONS PREFER_BOUNCY_CASTLE BANNER"
NAME="$1"
MAX_CONNECTIONS="$2"
PREFER_BOUNCY_CASTLE="$3"
BANNER="$4"

if [ "$#" -ne 4 ]; then
    printf "This replaces the configuration of a daemon. Nothing was sent: it needs all four arguments.\n"
    printf "%s\n" "${USAGE}"
    exit 2
fi
case "${NAME}" in
    ''|*[!A-Za-z0-9_-]*) printf "NAME is a daemon name such as ssh.\n%s\n" "${USAGE}"; exit 2 ;;
esac
if ! [[ "${MAX_CONNECTIONS}" =~ ^-?[0-9]{1,9}$ ]]; then
    printf "MAX_CONNECTIONS is a whole number, not %s.\n%s\n" "${MAX_CONNECTIONS}" "${USAGE}"
    exit 2
fi
if [ "${PREFER_BOUNCY_CASTLE}" != "true" ] && [ "${PREFER_BOUNCY_CASTLE}" != "false" ]; then
    printf "PREFER_BOUNCY_CASTLE is true or false, not %s.\n%s\n" "${PREFER_BOUNCY_CASTLE}" "${USAGE}"
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
printf "The daemon %s is now: %s\n" "${NAME}" "$(printf '%s' "${RESPONSE}" | jq -c .)"
printf "To put it back: ./03.daemons_name_PUT.sh %s %s %s %q\n" "${NAME}" \
  "$(printf '%s' "${RESPONSE}" | jq -r '.maxConnections')" \
  "$(printf '%s' "${RESPONSE}" | jq -r '.preferBouncyCastleProvider')" \
  "$(printf '%s' "${RESPONSE}" | jq -r '.banner // ""')"

BODY=$(jq -cn --arg max "${MAX_CONNECTIONS}" --arg bc "${PREFER_BOUNCY_CASTLE}" --arg banner "${BANNER}" \
  '{maxConnections: ($max | tonumber), preferBouncyCastleProvider: ($bc == "true"), banner: $banner}')

printf "Replacing the configuration of %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${NAME_URI}" -H "accept: application/json" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf "Done. The daemon takes the new settings when it restarts.\n"
