#!/bin/bash
# ==============================================================================
# Script Name: 01.configurations_PATCH.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script changes the first value of a Server Configuration Option, using the
# `/configurations/options/{name}` endpoint with the PATCH method.
# It demonstrates:
# - A JSON Patch `replace` of `/values/0`, built with jq
# - Reading and printing the old value first, with the command that puts it back
# - The HTTP code, and an exit of 1 when the server refuses
#
# Usage:
# ./01.configurations_PATCH.sh VALUE [OPTION]
#
#   VALUE   the new value. Required: with no value the script prints this usage, sends NOTHING and exits 2.
#           For the default option it is true or false
#   OPTION  the option's name (default AddressBook.Enabled), letters, digits, dots, dashes and underscores
#
# Risk: config - changes a Server Configuration Option of the whole server; put it back afterwards (the script prints how)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - An option holds a LIST of values, so the path targets an index: "/values/0" is the first value. Only that one is replaced.
# - Changing a Server Configuration Option affects the whole server, and the default option is a real feature switch (the address book), so there is no
#   default value: the value is an argument. The script prints the old values, and the command that puts the first one back, before it changes anything.
# - Requires `jq`, which builds the request body and reads the old value.
# - Confirmed directly: PATCH answers 204 with no body; GET of the option with `fields=values` answers `{"values": [...]}`. An option that does not exist is 404 on the
#   GET ("Configuration option with name X not found") and 400 on the PATCH ("Option with name \"X\" does not exist."). The `readOnly` flag an option carries does not stop
#   the API: `StatisticsSummaryReport.AutomaticReport.DaysToInclude`, which reads readOnly true, was patched and put back. The server does not check a value against what
#   the option means (the text "abc" was accepted for that number), so check it yourself; an encrypted option reads back as `{AES128}...` and a plain value sent to it is stored encrypted.
# - `replace` needs the value to exist. An option that holds no value is refused by this script (nothing sent): set it with 04.configurations_options_PUT.sh.
# - Exit codes: 0 when the server answered 204, 1 when the option cannot be read or the server refuses, 2 when the value or the option name is missing or wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations/options"
DEFAULT_OPTION="AddressBook.Enabled"
USAGE="Usage: 01.configurations_PATCH.sh VALUE [OPTION]   (OPTION is ${DEFAULT_OPTION} when left out)"
VALUE="$1"
OPTION="${2:-${DEFAULT_OPTION}}"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "${VALUE}" ]; then
    printf "This changes a Server Configuration Option of the whole server. Nothing was sent: it needs the new value.\n"
    printf "%s\n" "${USAGE}"
    exit 2
fi
case "${OPTION}" in
    ''|*[!A-Za-z0-9._-]*) printf "OPTION is an option name such as %s.\n%s\n" "${DEFAULT_OPTION}" "${USAGE}"; exit 2 ;;
esac
if [ "${OPTION}" = "${DEFAULT_OPTION}" ] && [ "${VALUE}" != "true" ] && [ "${VALUE}" != "false" ]; then
    printf "VALUE for %s is true or false, not %s.\n%s\n" "${OPTION}" "${VALUE}" "${USAGE}"
    exit 2
fi

OPTION_URI=$(jq -rn --arg name "${OPTION}" '$name | @uri')

printf "Reading the option %s...\n" "${OPTION}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/${OPTION_URI}" --data-urlencode "fields=values" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the option %s: HTTP %s\n" "${OPTION}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf "The values of %s are now: %s\n" "${OPTION}" "$(printf '%s' "${RESPONSE}" | jq -c '.values')"
if [ "$(printf '%s' "${RESPONSE}" | jq '(.values // []) | length')" = "0" ]; then
    printf "The option holds no value, and replace needs one. Nothing was sent: set it with 04.configurations_options_PUT.sh.\n"
    exit 1
fi
printf "To put the first one back: ./01.configurations_PATCH.sh %q %s\n" "$(printf '%s' "${RESPONSE}" | jq -r '.values[0]')" "${OPTION}"

BODY=$(jq -cn --arg value "${VALUE}" '[{op: "replace", path: "/values/0", value: $value}]')

printf "Setting %s to %s...\n" "${OPTION}" "${VALUE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${OPTION_URI}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
