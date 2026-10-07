#!/bin/bash
# ==============================================================================
# Script Name: 02.deniedUsers_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script adds a login name to the denied users using the `/deniedUsers`
# endpoint: the name can no longer log in, for good or for a number of hours.
#
# Usage:
# ./02.deniedUsers_POST.sh [LOGIN_NAME [HOURS [NOTE]]]
#
#   LOGIN_NAME  the name to block (default example_denied)
#   HOURS       block for this many hours; leave out to block for good
#   NOTE        why (optional)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - 03.deniedUsers_name_DELETE.sh removes the name again.
# - The answer is 201 with the new entry's address in the Location header, and no
#   body. A name that is already in the list answers 400 "already exists in the
#   block list"; no loginName answers 400 "loginName must not be null".
# - Confirmed directly: the server accepts an EMPTY loginName, and the entry
#   then cannot be removed through the API (DELETE with an empty name answers
#   405). This script refuses an empty name, and so should anything calling the
#   endpoint.
# - Confirmed directly: the server also accepts 0 and negative HOURS, which give
#   an entry that has already expired; this script asks for 1 or more.
# - Confirmed directly: a blocked name is refused at the EndUser login with 401
#   "Login failed", and logs in again once it is removed. Blocking the login name
#   of a real account stops them logging in: choose the name with care.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/deniedUsers"
LOGIN_NAME="${1:-example_denied}"
HOURS="$2"
NOTE="$3"
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT
if [ -z "${LOGIN_NAME// /}" ]; then
    printf "LOGIN_NAME must not be empty: the server would accept it and then not let it be removed.\n"
    exit 2
fi
if [ -n "${HOURS}" ] && ! [[ "${HOURS}" =~ ^[1-9][0-9]*$ ]]; then
    printf "HOURS must be a whole number of 1 or more: %s\n" "${HOURS}"
    exit 2
fi

# ttl is left out for a permanent block
BODY=$(jq -cn --arg name "${LOGIN_NAME}" --arg hours "${HOURS}" --arg note "${NOTE}" \
  '{loginName: $name} + (if $hours != "" then {ttl: ($hours | tonumber)} else {} end) + (if $note != "" then {note: $note} else {} end)')

DURATION="for good"
[ -n "${HOURS}" ] && DURATION="for ${HOURS} hours"
printf "Blocking %s %s...\n" "${LOGIN_NAME}" "${DURATION}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -D "${HEADERS_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
printf "It is at %s\n" "$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r')"
