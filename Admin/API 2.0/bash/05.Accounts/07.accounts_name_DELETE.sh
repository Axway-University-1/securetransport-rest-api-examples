#!/bin/bash
# ==============================================================================
# Script Name: 07.accounts_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes accounts using the `/accounts/{name}` endpoint.
# For each account it first reads it, to say what it is about to delete. If it exists, the account is deleted.
# Otherwise a message is printed.
#
# By default it cleans up the three accounts created by 02.accounts_POST.sh.
#
# Usage:
# ./07.accounts_name_DELETE.sh [NAME...]
#
#   NAME  the accounts to delete (default example_user, example_service and example_template, the ones 02.accounts_POST.sh creates)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This script deletes data. Check the account names before running it: any account can be named, and the delete cannot be undone.
#   Deleting an account removes its certificates and subscriptions but leaves its home folder, with its files, on disk (see st-api-gotchas).
# - Each account is read first and what it is (type, home folder, uid) is printed, so that it can be created again with 02.accounts_POST.sh or by hand.
# - Requires `jq`, which URL-encodes each name and reads the account.
# - Confirmed directly: a delete is 204 with no body; an account that is not there is 404 on the read and on the delete.
# - Exit codes: 0 when every account named was deleted or was not there, 1 when the server refused one (the others are still tried), 2 when a name is empty (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts"
if [ "$#" -gt 0 ]; then
    NAMES=("$@")
else
    NAMES=(example_user example_service example_template)
fi
for NAME in "${NAMES[@]}"; do
    if [ -z "${NAME}" ]; then
        printf "An account name must not be empty.\nUsage: 07.accounts_name_DELETE.sh [NAME...]\n"
        exit 2
    fi
done

FAILED=0
for NAME in "${NAMES[@]}"; do
    NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')

    # Let's say that we want to delete an Account.
    # For the purpose we will first read it, with a few fields only, to say what we are deleting.
    # If it exists, we will delete it.
    # Otherwise will print message that it doesn't exist.
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/${NAME_URI}" --data-urlencode "fields=type,homeFolder,uid" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" = "404" ]; then
        printf "Account %s does not exist.\n" "${NAME}"
        continue
    fi
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not read the account %s: HTTP %s\n" "${NAME}" "${HTTP_CODE}"
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        FAILED=1
        continue
    fi
    printf "Deleting Account: %s (%s)\n" "${NAME}" "$(printf '%s' "${RESPONSE}" | jq -r '"type \(.type), home folder \(.homeFolder), uid \(.uid)"')"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${NAME_URI}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "204" ]; then
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        FAILED=1
    fi
done
exit "${FAILED}"
