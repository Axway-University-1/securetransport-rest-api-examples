#!/bin/bash
# ==============================================================================
# Script Name: 06.userClasses_id_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script changes one property of a user class, using the `/userClasses/{id}`
# endpoint with PATCH: a JSON Patch document that replaces one field. Unlike PUT
# (05.userClasses_id_PUT.sh), it sends only what changes.
#
# Usage:
# ./06.userClasses_id_PATCH.sh [NAME [FIELD [VALUE]]]
#
#   NAME   the class (default example_userclass)
#   FIELD  enabled (default), expression, order, userName, group, address, userType or className
#   VALUE  the new value (default true); true or false for enabled, a number from 1 for order, none to empty the expression
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the value before, to put it back with. A change of `order` moves the class and the others shift: the one at that
#   place and those after it go down by one, so patching VirtClass or RealClass would change which classes come first: do not.
# - Confirmed directly: a success answers 204, with no body, and an empty patch is 204 too. `replace` works on every field of the class;
#   `add` on one that is set overwrites it; `remove` of `/expression` gives the empty text (not null); `remove` of any other field is 400
#   "group must not be null" (and so on). `replace` of `/id` is 204 and changes nothing; a path that does not exist is 400 `Missing field
#   "nope"`; `enabled` with text that is no boolean is 400; an invalid expression, userType or a name another class has is 400 or 409
#   and the class is unchanged; `className` renames it (the accounts in it are in it still, under the new name). An unknown id is 400, not
#   the 404 the reference lists.
# - Confirmed directly, the effect on a login: patching `expression`, `enabled`, `userName` or `userType` so that the account no longer fits
#   puts its NEXT login (SFTP, HTTP and FTP alike) in the next matching class, and patching it back puts it in again. Of two classes that fit, the one with the lower
#   `order` wins: patching `/order` of the second to 1 (or of the first to 2) swaps them. A session already open keeps its class. Check 60.
# - Requires `jq`, which reads the id and builds the patch.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/userClasses"
NAME="${1:-example_userclass}"
FIELD="${2:-enabled}"
VALUE="${3:-true}"
case "${FIELD}" in
    enabled) KIND=boolean ;;
    order) KIND=number ;;
    expression|userName|group|address|userType|className) KIND=string ;;
    *) printf "FIELD is enabled, expression, order, userName, group, address, userType or className, not %s.\n" "${FIELD}"; exit 2 ;;
esac
if [ "${KIND}" = "boolean" ] && [ "${VALUE}" != "true" ] && [ "${VALUE}" != "false" ]; then
    printf "VALUE for enabled is true or false, not %s.\n" "${VALUE}"
    exit 2
fi
if [ "${KIND}" = "number" ] && { ! [[ "${VALUE}" =~ ^[0-9]+$ ]] || [ "${VALUE}" -lt 1 ]; }; then
    printf "VALUE for order is a number from 1, not %s.\n" "${VALUE}"
    exit 2
fi
if [ -z "${VALUE}" ]; then
    printf "VALUE must not be empty (use none for an empty expression).\n"
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

CLASS_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${CLASS_ID}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${CLASS_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the user class %s (id %s).\n" "${NAME}" "${CLASS_ID}"
    exit 1
fi

printf "The %s of %s is now '%s'.\n" "${FIELD}" "${NAME}" "$(printf '%s' "${CLASS_JSON}" | jq -r --arg field "${FIELD}" '.[$field] | tostring')"
BODY=$(jq -cn --arg path "/${FIELD}" --arg value "${VALUE}" --arg kind "${KIND}" \
  '[{op: "replace", path: $path, value: (if $kind == "boolean" then ($value == "true")
                                         elif $kind == "number" then ($value | tonumber)
                                         elif $value == "none" then ""
                                         else $value end)}]')

printf "Setting it to %s...\n" "${VALUE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${CLASS_ID}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
