#!/bin/bash
# ==============================================================================
# Script Name: 04.accounts_name_GET.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves one account using the `/accounts/{name}` endpoint.
# It demonstrates:
# - Retrieving everything about an account
# - Selecting individual fields
# - That a field specific to one account type needs the type in the request
#
# Usage:
# ./04.accounts_name_GET.sh [NAME]
#
#   NAME  the account (default example_user, the one 02.accounts_POST.sh creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The type is always returned, even when it is not listed in the fields.
# - Confirmed directly (5.5-20260924): `fields=addressBookSettings` without `type=user` is refused, 400 "Field addressBookSettings does not exist." (older notes say it answers
#   only the type); with `type=user` it answers the settings. That third call is the demonstration of it, so its refusal is shown and does not stop the script. The whole object,
#   read with no `fields`, carries `addressBookSettings` without any `type`.
# - Exit codes: 0 when every call but that one answered 200, 1 when one did not.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts"
NAME="${1:-example_user}"
NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')

# get_account QUERY [demo]: GET the account with the query string given; print the answer, and stop when it is not 200
# (a call given as "demo" is expected to be refused, so its answer is shown and the script goes on)
get_account() {
    printf "GET /api/v2.0/accounts/%s%s\n" "${NAME_URI}" "$1"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${NAME_URI}$1" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf '%s\n' "${RESPONSE}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        [ "$2" = "demo" ] || exit 1
    fi
}

# Simple GET to retrieve everything about a specific account
get_account ""

# GET only the name, uid, and gid
# Pay attention that the type is also returned no matter that it is not specified in the fields
get_account "?fields=name,uid,gid"

# If we want to receive fields that are not common to all account types, but are specific to the user one, we have to specify the type
# Let's try with the addressBookSettings and without the type
get_account "?fields=addressBookSettings" demo

# And now by specifying the type=user
get_account "?type=user&fields=addressBookSettings"
