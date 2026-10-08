#!/bin/bash
# ==============================================================================
# Script Name: 04.userClasses_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves one user class, using the `/userClasses/{id}` endpoint.
# The path takes the class's id, so the script looks the id up by name first.
# It prints a short summary of the class, then only some fields of it.
#
# Usage:
# ./04.userClasses_id_GET.sh [NAME]
#
#   NAME  the class (default example_userclass)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The class is looked up by name, and must be the only one with that name.
# - Confirmed directly: the object has `id`, `className`, `userType`, `userName`, `group`, `address`, `expression` (the empty text
#   when none), `enabled` and `order`, and no `metadata`. An unknown id, well formed or not, is a JSON 404 "User Class with ID \"X\"
#   does not exist."; `fields=` keeps the keys named and an unknown field is 400.
# - Requires `jq`, which reads the id and prints the summary.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/userClasses"
NAME="${1:-example_userclass}"
if [ "$#" -gt 1 ]; then
    printf "Usage: ./04.userClasses_id_GET.sh [NAME]\n"
    exit 2
fi

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

# The one class with that name: "1 <id>", or how many there are.
# The className filter ignores case and takes a * wildcard, so the exact name
# is picked out of what comes back.
st_get -G "${MAIN_URL}" --data-urlencode "className=${NAME}" --data-urlencode "fields=id,className"
read -r FOUND CLASS_ID < <(printf '%s\n' "${RESPONSE}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.className == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s user classes named %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}"
    exit 1
fi

printf "The user class %s, id %s:\n" "${NAME}" "${CLASS_ID}"

st_get "${MAIN_URL}/${CLASS_ID}"
CLASS_JSON="${RESPONSE}"
if ! printf '%s' "${CLASS_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the user class %s (id %s).\n" "${NAME}" "${CLASS_ID}"
    exit 1
fi

printf '%s' "${CLASS_JSON}" | jq -r '"  order:      \(.order)\n  type:       \(.userType)\n  user name:  \(.userName)\n  group:      \(.group)\n  address:    \(.address)\n  enabled:    \(.enabled)\n  expression: \(if .expression == "" then "-" else .expression end)"'

printf "\nOnly some fields of it:\n"
st_get -G "${MAIN_URL}/${CLASS_ID}" --data-urlencode "fields=className,enabled"
printf '%s' "${RESPONSE}"
printf "\n"
