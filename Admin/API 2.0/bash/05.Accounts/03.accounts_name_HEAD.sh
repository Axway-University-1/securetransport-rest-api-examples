#!/bin/bash
# ==============================================================================
# Script Name: 03.accounts_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether an account exists, using the `/accounts/{name}` endpoint with the HEAD method.
# It demonstrates:
# - HEAD, which returns the headers only and so is a cheap existence check
# - Reading the HTTP code with curl itself (`-w`), and acting on it
#
# Usage:
# ./03.accounts_name_HEAD.sh [NAME]
#
#   NAME  the account (default example_user, the one 02.accounts_POST.sh creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: 200 when the account exists and 404 when it does not, with no body either way.
# - Exit codes: 0 when the account exists, 1 when it does not (404) or the server answers otherwise.
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

# The HTTP code comes from curl itself. A bare --head would print the headers instead, and
# curl -I does the same as --head.
HTTP_CODE=$(curl -s -o /dev/null -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${NAME_URI}" -H "accept: */*" -H "${REFERER_HEADER}" -w "%{http_code}")
printf "HTTP %s\n" "${HTTP_CODE}"

if [ "${HTTP_CODE}" = "200" ]; then
    echo "Account Exists"
elif [ "${HTTP_CODE}" = "404" ]; then
    echo "Account does not exist"
    exit 1
else
    printf "Could not tell whether the account exists.\n"
    exit 1
fi
