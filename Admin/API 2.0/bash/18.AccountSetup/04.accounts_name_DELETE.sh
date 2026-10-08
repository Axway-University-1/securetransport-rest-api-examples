#!/bin/bash
# ==============================================================================
# Script Name: 04.accounts_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script removes the account 01.accountSetup_POST.sh sets up, using the
# `/accounts/{name}` endpoint. /accountSetup has no DELETE of its own:
# deleting the account removes what was set up with it.
#
# Usage:
# ./04.accounts_name_DELETE.sh [ACCOUNT]
#
#   ACCOUNT  the account to remove (default example_setup, which 01.accountSetup_POST.sh creates)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: deleting the account also deletes its transfer sites
#   and transfer profiles.
# - The files in the account's home folder stay on disk. See
#   05.Accounts/07.accounts_name_DELETE.sh.
# - Only ever point it at an account you set up. The delete cannot be undone: the account is read first and what it is (type, home folder and uid)
#   is printed, so that it can be set up again with 01.accountSetup_POST.sh or by hand.
# - Requires `jq`, which URL-encodes the name and reads the account.
# - Confirmed directly: a delete is 204 with no body; an account that is not there is 404 on the read and on the delete.
# - Exit codes: 0 when the account was deleted (204) or was not there, 1 when the server refuses or the account cannot be read, 2 when the name
#   is empty (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts"

ACCOUNT="${1:-example_setup}"
if [ "$#" -gt 1 ] || [ -z "${ACCOUNT// /}" ]; then
    printf "Usage: ./04.accounts_name_DELETE.sh [ACCOUNT]\n"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${ACCOUNT}" '$name | @uri')

# Read it first, with a few fields only, to say what is being deleted
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/${ENCODED}" --data-urlencode "fields=type,homeFolder,uid" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" = "404" ]; then
    printf "Account %s does not exist.\n" "${ACCOUNT}"
    exit 0
fi
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the account %s: HTTP %s\n" "${ACCOUNT}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi

printf "Deleting the account %s (%s), with its sites and profiles...\n" "${ACCOUNT}" "$(printf '%s' "${RESPONSE}" | jq -r '"type \(.type), home folder \(.homeFolder), uid \(.uid)"')"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
