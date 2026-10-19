#!/bin/bash
# ==============================================================================
# Script Name: 05.myself_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script performs a POST request to the `/myself` endpoint, which is related
# to user authentication. It initiates a session or validates credentials depending
# on the API implementation.
#
# Usage:
# ./05.myself_POST.sh
#
# Risk: read
#
# Notes:
# - For complete documentation, refer to folder 01.Authentication.
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - Confirmed directly: the answer to a login is 200 {"message": "Logged in"}; 401 with the plain text "Authentication
#   required." for refused credentials. The script prints the status and the answer when it is not 200, and exits 1.
# - 01.Authentication/01.myself_POST.sh makes the same call.
# - Exit codes: 0 when the login is accepted (200), 1 otherwise.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ADMIN_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}"
