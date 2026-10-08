#!/bin/bash
# ==============================================================================
# Script Name: 06.accounts_name_PATCH_with_file.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script performs a partial update to an account using the
# `/accounts/{name}` endpoint, reading the PATCH body from a file instead of
# building it on the command line.
# It demonstrates:
# - Keeping the request body in a separate, reusable JSON file
# - Printing what the paths of that file hold now, so that the change can be put back
# - Checking the HTTP response code instead of printing the whole response
#
# Usage:
# ./06.accounts_name_PATCH_with_file.sh [NAME [PATCH_FILE]]
#
#   NAME        the account (default example_user, the one 02.accounts_POST.sh creates)
#   PATCH_FILE  a JSON Patch body: a list of operations (default 06.patch_body/stPatchAccount.json, next to the script)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The 06.patch_body folder holds one file per example change. Give the one you want as the second argument. A file that is missing, or is not a list of
#   operations with an `op` and a `path` each, is refused with exit 2 and nothing is sent.
# - 06.patch_body/README.md says the same, next to the files (a JSON file cannot carry a comment).
# - The samples are not all harmless anywhere. stPatchAccount.json (the default) and stPatchAccountContacts.json add a contact, stPatchAccountNotes.json sets the notes and
#   stPatchAccountForcePasswordChange.json turns forcePasswordChange off: they work on any user account. stPatchAccountBU.json names things that exist only in one
#   environment: it moves the account into the business unit `Pippin` and sets the home folder to `/usrdata/BU/Pippin/t3`, so it is refused (404
#   "Business unit with name Pippin not found or not accessible.") on a server without that unit, and it must be adapted to your own business unit and base folder before it is used.
#   The contact samples carry made up addresses (a@b.com1 and a22@1b.com1): replace them with real ones if the contact is to be used.
# - Before it changes anything the script reads the account and prints what each path of the file holds now (null when the path is not there yet, as with the end of an array).
#   Taking an added contact out again is a `remove` of its index (see 06.accounts_name_PATCH.sh); for a `replace`, send the old value back.
# - Requires `jq`, which reads the paths and what they hold now.
# - Confirmed directly: a success is 204 with no body; a business unit that does not exist is 404; a path that does not exist is 400 `Missing field "nope"`.
# - Exit codes: 0 when the server answered 204, 1 when the account cannot be read or the server refuses, 2 when the body file is missing or is not a JSON Patch (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts"
NAME="${1:-example_user}"
PATCH_FILE="${2:-${SCRIPT_DIR}/06.patch_body/stPatchAccount.json}"
USAGE="Usage: 06.accounts_name_PATCH_with_file.sh [NAME [PATCH_FILE]]"
if [ "$#" -gt 2 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
if [ ! -f "${PATCH_FILE}" ]; then
    printf "The patch body %s is not a file.\n%s\n" "${PATCH_FILE}" "${USAGE}"
    exit 2
fi
if ! jq -e 'type == "array" and length > 0 and all(.[]; type == "object" and has("op") and has("path"))' "${PATCH_FILE}" >/dev/null 2>&1; then
    printf "%s is not a JSON Patch: a list of operations, each with an op and a path.\n%s\n" "${PATCH_FILE}" "${USAGE}"
    exit 2
fi
NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')

printf "Reading the account %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/${NAME_URI}" --data-urlencode "fields=type" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the account %s: HTTP %s\n" "${NAME}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
ACCOUNT_TYPE=$(printf '%s' "${RESPONSE}" | jq -r '.type')
# Fields that belong to one account type, like addressBookSettings, are only returned with the type
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/${NAME_URI}" --data-urlencode "type=${ACCOUNT_TYPE}" \
  -H "accept: application/json" -H "${REFERER_HEADER}")

# What each path of the patch holds now: "-" at the end of a path is a new element of an array, which has no value yet
printf "What the paths hold now:\n"
printf '%s' "${RESPONSE}" | jq -r --slurpfile patch "${PATCH_FILE}" '
  . as $account | $patch[0][] | .path as $path
  | ($path | ltrimstr("/") | split("/") | map(if test("^[0-9]+$") then tonumber else . end)) as $parts
  | "  \($path): \($account | try getpath($parts) catch null | tojson)"'

ELEMENT_TO_BE_CHANGED=$(jq -r '[.[] | .path] | join(", ")' "${PATCH_FILE}")
printf "Changing '%s' of account '%s'...\n" "${ELEMENT_TO_BE_CHANGED}" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${NAME_URI}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "@${PATCH_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"

if [[ "${HTTP_CODE}" == "204" ]]; then
  echo "Account '${NAME}' has been changed successfully."
else
  echo "Account '${NAME}' update failed."
  printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
  exit 1
fi
