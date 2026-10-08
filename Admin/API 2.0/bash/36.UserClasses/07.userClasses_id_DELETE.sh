#!/bin/bash
# ==============================================================================
# Script Name: 07.userClasses_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a user class, using the `/userClasses/{id}` endpoint.
# A class is deleted by its id, not its name, so it looks the id up by name first.
#
# Usage:
# ./07.userClasses_id_DELETE.sh NAME
#
#   NAME  the class (required). VirtClass and RealClass are refused
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This deletes data. Check the name before running it; 02.userClasses_POST.sh creates `example_userclass`. VirtClass and RealClass
#   are the classes the server's logins fall back to: the script refuses them (exit 2), the server would not.
# - Confirmed directly: a success is 204. An unknown id (or a second delete) is 400 "User Class with ID X does not exist.", not 404.
#   Nothing stops the delete of a class that is IN USE: with a template account whose `templateClass` names it (the template keeps the
#   name, and the server never checked that a class by that name exists when the template was created: 201), or with a session open in
#   it (the session stays open and is still listed under the class's name). The next login of an account that was in it is in the next
#   class that fits, VirtClass for a local account. The classes after it move up one place; the lab's own two are as they were.
# - Requires `jq`, which reads the id.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/userClasses"
NAME="$1"
[ -n "${NAME}" ] || { printf "Usage: ./07.userClasses_id_DELETE.sh NAME\n"; exit 2; }
if [ "${NAME}" = "VirtClass" ] || [ "${NAME}" = "RealClass" ]; then
    printf "%s is one of the server's own classes. Refused.\n" "${NAME}"
    exit 2
fi

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

printf "Deleting the user class %s (%s)...\n" "${NAME}" "${CLASS_ID}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${CLASS_ID}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
