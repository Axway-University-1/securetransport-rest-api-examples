#!/bin/bash
# ==============================================================================
# Script Name: 01.myself_cookie_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script performs basic authentication against the API using a cookie jar
# to persist session information. It reduces the need for repeated authentication
# across multiple requests.
#
# Usage:
# ./01.myself_cookie_POST.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The cookie jar file will store session data for reuse.
# - Confirmed directly: the login answers 200 {"message": "Logged in"} and a csrfToken header; the read that follows
#   with the jar answers 200 with the administrator's data. A refused login (401, "Authentication required." as plain
#   text) or a refused read prints the status and the answer and exits 1; the jar is removed when the login fails.
# - Exit codes: 0 when both calls answer 200, 1 otherwise.
# ==============================================================================

printf "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

printf "\n\nBasic authentication with cookie jar to reduce further authentications...\n"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# Authenticate and store session in cookie jar
LOGIN_HEADERS=$(mktemp)
RESPONSE=$(curl -s -k --cookie-jar cookie.jar -D "${LOGIN_HEADERS}" -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    rm -f "${LOGIN_HEADERS}" cookie.jar
    printf "HTTP %s\n" "${HTTP_CODE}"
    [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}"

#
# CSRF is enforced on session-cookie calls from the 20230525 release onward.
# The token comes back once, in this login response's own csrfToken header,
# and must be sent back on every later call in the session - a Basic auth
# call carrying no cookie is exempt, but this script keeps a session, so it
# is not.
#
CSRF_TOKEN=$(grep -i "^csrfToken:" "${LOGIN_HEADERS}" | tr -d '\r' | cut -d' ' -f2-)
rm -f "${LOGIN_HEADERS}"

# Reuse session to make a GET request
RESPONSE=$(curl -s -k --cookie cookie.jar -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}"
