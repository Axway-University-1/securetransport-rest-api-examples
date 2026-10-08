#!/bin/bash
# ==============================================================================
# Script Name: 05.userClasses_id_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a user class, using the `/userClasses/{id}` endpoint with PUT:
# it reads the class, changes the membership expression and/or whether it is enabled, and sends the
# whole class back.
#
# Usage:
# ./05.userClasses_id_PUT.sh [NAME [EXPRESSION [ENABLED]]]
#
#   NAME        the class (default example_userclass)
#   EXPRESSION  the new expression (default false); none empties it; - leaves it alone
#   ENABLED     true or false; - (default) leaves it alone
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the values before, to put them back with. Nothing to change (both left alone) is exit 2, nothing sent.
# - PUT replaces the whole class. Confirmed directly: a body with only the five required fields (className, userType, userName,
#   group, address) answers 204 and RESETS `expression` to the empty text and `enabled` to false; `order` is kept when left out. That is
#   why the class is read first and sent back with one or two fields changed. `id` is dropped from the body (a body that carries the
#   id of ANOTHER class is accepted and ignored: the path decides).
# - Confirmed directly: a success answers 204, with no body. A body missing a required field is 400 listing it; an invalid
#   expression is 400 "expression X is not valid." and the class is unchanged; `className` renames it (a name another class has, 409; the
#   same name in other capitals is fine); `order` moves the class: 0 or 1 first, the ones in between shift, more than there are classes
#   or a negative one is 400 "Order is not valid.". An unknown id is 400 "User Class with ID X does not exist.", not the 404 the
#   reference lists. The reference leaves `enabled`, `expression` and `order` optional, as they are.
# - Confirmed directly, the effect: after a PUT that makes the expression false, or `enabled` false, the next login (SFTP, HTTP or FTP alike) of an account the
#   class fitted is in the next matching class (VirtClass); put back, it is in the class again, at once. A session already open keeps
#   the class it had. Check 60 shows it.
# - Requires `jq`, which reads the id and edits the class.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/userClasses"
NAME="${1:-example_userclass}"
EXPRESSION="${2:-false}"
ENABLED="${3:--}"
case "${ENABLED}" in
    true|false|-) ;;
    *) printf "ENABLED is true, false or -, not %s.\n" "${ENABLED}"; exit 2 ;;
esac
if [ "${EXPRESSION}" = "-" ] && [ "${ENABLED}" = "-" ]; then
    printf "Nothing to change: give an EXPRESSION or ENABLED.\n"
    exit 2
fi
if [ "${#EXPRESSION}" -gt 1024 ]; then
    printf "EXPRESSION is 1024 characters at most.\n"
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

printf "The expression of %s is now '%s', enabled is %s.\n" "${NAME}" "$(printf '%s' "${CLASS_JSON}" | jq -r '.expression')" "$(printf '%s' "${CLASS_JSON}" | jq -r '.enabled')"
BODY=$(printf '%s' "${CLASS_JSON}" | jq -c --arg expression "${EXPRESSION}" --arg enabled "${ENABLED}" \
  '(if $expression != "-" then .expression = (if $expression == "none" then "" else $expression end) else . end)
   | (if $enabled != "-" then .enabled = ($enabled == "true") else . end) | del(.id)')

printf "Changing it...\n"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${CLASS_ID}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
