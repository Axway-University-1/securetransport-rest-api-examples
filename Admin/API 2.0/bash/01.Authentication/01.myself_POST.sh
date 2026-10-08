#!/bin/bash
# ==============================================================================
# Script Name: 01.myself_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script logs in to the API with basic authentication, using POST on the
# `/myself` endpoint, and prints the server's answer.
#
# Usage:
# ./01.myself_POST.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This script does not use a cookie jar, so authentication is required for each call.
# - POST /myself is the LOGIN call. Confirmed directly: it answers 200 with {"message": "Logged in"}, not the
#   administrator's data; GET /myself (02.Introduction/03.myself_GET.sh) answers that. An earlier version of this
#   script sent a GET, which made it a copy of that one. 02.Introduction/05.myself_POST.sh makes the same call.
# - Confirmed directly: wrong credentials, or none, answer 401 with the plain text "Authentication required."
#   (text/html), not JSON. The script prints the status and that answer, and exits 1.
# - Exit codes: 0 when the login is accepted (200), 1 for any other status.
# ==============================================================================
printf "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

printf "\n\nBasic authentication: logging in with POST /myself...\n"

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
