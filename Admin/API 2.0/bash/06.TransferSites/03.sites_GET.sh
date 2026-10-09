#!/bin/bash
# ==============================================================================
# Script Name: 03.sites_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves transfer sites using the `/sites` endpoint.
# It demonstrates:
# - A GET request for all the sites of one account
# - A GET request filtered by protocol, printed as one line per site
#
# Usage:
# ./03.sites_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This example uses the account "john". 02.sites_POST_ssh.sh creates two SSH
#   sites for it.
# - Requires `jq`, which prints the short listing.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when both answers are 200, 1 otherwise.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"

ACCOUNT="${ST_EXAMPLE_ACCOUNT:-john}"

# st_get CURL_ARGUMENTS...: a GET of the URL given (with any curl options, such as -G --data-urlencode ...). The answer
# is left in RESPONSE. A status other than 200 ends the script with exit 1, after printing the status and the answer.
st_get() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "$@" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}

printf "Get all the sites of the account '%s'...\n" "${ACCOUNT}"
st_get "${MAIN_URL}?account=${ACCOUNT}"
printf '%s' "${RESPONSE}"

printf "\n\nGet only its SSH sites, one line each: id, name, host:port, folder...\n"
st_get "${MAIN_URL}?account=${ACCOUNT}&protocol=ssh"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "\(.id)  \(.name)  \(.host):\(.port)  \(.downloadFolder // .uploadFolder // "")"'
