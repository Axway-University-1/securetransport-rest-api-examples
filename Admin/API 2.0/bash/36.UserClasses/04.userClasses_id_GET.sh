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
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/userClasses"
NAME="${1:-example_userclass}"

# The one class with that name: "1 <id>", or how many there are.
# The className filter ignores case and takes a * wildcard, so the exact name
# is picked out of what comes back.
read -r FOUND CLASS_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
  --data-urlencode "className=${NAME}" --data-urlencode "fields=id,className" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.className == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s user classes named %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}"
    exit 1
fi

printf "The user class %s, id %s:\n" "${NAME}" "${CLASS_ID}"

CLASS_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${CLASS_ID}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${CLASS_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the user class %s (id %s).\n" "${NAME}" "${CLASS_ID}"
    exit 1
fi

printf '%s' "${CLASS_JSON}" | jq -r '"  order:      \(.order)\n  type:       \(.userType)\n  user name:  \(.userName)\n  group:      \(.group)\n  address:    \(.address)\n  enabled:    \(.enabled)\n  expression: \(if .expression == "" then "-" else .expression end)"'

printf "\nOnly some fields of it:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/${CLASS_ID}" --data-urlencode "fields=className,enabled" \
  -H "accept: application/json" -H "${REFERER_HEADER}"
printf "\n"
