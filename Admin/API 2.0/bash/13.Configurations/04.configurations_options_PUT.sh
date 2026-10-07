#!/bin/bash
# ==============================================================================
# Script Name: 04.configurations_options_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes several Server Configuration Options in one call, using
# the `/configurations/options` endpoint with PUT: a list of names, each with
# its new values.
#
# Usage:
# ./04.configurations_options_PUT.sh NAME=VALUE...
#
#   NAME=VALUE  an option and its new value, one argument each (default:
#               AddressBook.Limit.DefaultDisplayEntries=10 and
#               AddressBook.Limit.MaxDisplayEntries=100, their usual values)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A configuration applies to the whole server: every account and every user.
# - It prints each option's values before the change, to put them back with.
# - Only values change; a name that does not exist answers 404 and nothing is
#   changed.
# - To clear an option, send an empty string: NAME= sends [""]. An empty list
#   answers 400 "Invalid argument length."
# - 01.configurations_PATCH.sh changes one option with PATCH.
# - Requires `jq`, which builds the body and reads the options.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
if [ "$#" -eq 0 ]; then
    set -- "AddressBook.Limit.DefaultDisplayEntries=10" "AddressBook.Limit.MaxDisplayEntries=100"
fi
for PAIR in "$@"; do
    [[ "${PAIR}" == *=* ]] || { printf "Each argument is NAME=VALUE, not %s.\n" "${PAIR}"; exit 2; }
done

# [{"name": NAME, "values": [VALUE]}, ...]
BODY=$(jq -cn '[$ARGS.positional[] | capture("^(?<name>[^=]+)=(?<value>.*)$") | {name, values: [.value]}]' --args "$@")

printf "Before:\n"
for NAME in $(printf '%s' "${BODY}" | jq -r '.[].name'); do
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/options/${NAME}?fields=name,values" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '"  \(.name) = \(.values // [] | join(", "))"'
done

printf "Setting:\n"
printf '%s' "${BODY}" | jq -r '.[] | "  \(.name) = \(.values | join(", "))"'
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/options" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
