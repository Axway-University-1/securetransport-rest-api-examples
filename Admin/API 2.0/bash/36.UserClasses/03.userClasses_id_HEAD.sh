#!/bin/bash
# ==============================================================================
# Script Name: 03.userClasses_id_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a user class exists, using the `/userClasses/{id}`
# endpoint with HEAD: 200 when it does, 404 when it does not. The path takes the class's id,
# so the script looks the id up by name first.
#
# Usage:
# ./03.userClasses_id_HEAD.sh [NAME]
#
#   NAME  the class (default example_userclass)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The class is looked up by name, and must be the only one with that name.
# - Confirmed directly: HEAD answers 200, or 404 with no body, also for an id that is not well formed. The path takes the id: the
#   NAME in the path (`/userClasses/VirtClass`) is a 404. The `className=` filter ignores case and takes a * wildcard, so `example_x`
#   and `EXAMPLE_X` (two classes) both come back for either and `example*` finds both: the script keeps only the exact name.
# - Requires `jq`, which reads the id.
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

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${CLASS_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The user class %s exists, id %s.\n" "${NAME}" "${CLASS_ID}"
else
    printf "The user class %s, id %s, does not exist (HTTP %s).\n" "${NAME}" "${CLASS_ID}" "${HTTP_CODE}"
    exit 1
fi
