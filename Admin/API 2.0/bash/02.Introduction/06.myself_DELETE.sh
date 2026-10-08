#!/bin/bash
# ==============================================================================
# Script Name: 06.myself_DELETE.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates how to log in using basic authentication and a cookie jar,
# then log out by sending a DELETE request to the `/myself` endpoint.
# It also verifies session status before and after logout.
#
# Usage:
# ./06.myself_DELETE.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The cookie jar is used to persist session state across requests.
# - Confirmed directly: the login answers 200 {"message": "Logged in"}, the read 200, the logout 200 {"message": "Logged out"},
#   and the read after it 401 with the plain text "Authentication required.": that is how this script knows the session ended.
# - Every call is checked: a login, a read or a logout that is not 200 prints the status and the answer and ends the script
#   with exit 1; so does a last read that is still 200 (the session did not end). The jar is left in the folder, as before.
# - Exit codes: 0 when the session was opened, read, closed and then refused (401 or 403), 1 otherwise.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# Authenticate and store session
LOGIN_HEADERS=$(mktemp)
RESPONSE=$(curl -s -k --cookie-jar cookie.jar -D "${LOGIN_HEADERS}" -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
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

# Verify session is active
RESPONSE=$(curl -s -k --cookie cookie.jar -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}"

# Log out
RESPONSE=$(curl -s -k -L --cookie cookie.jar -X DELETE "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}"

# Verify session is terminated: the server must now refuse the jar
RESPONSE=$(curl -s -k --cookie cookie.jar -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "401" ] && [ "${HTTP_CODE}" != "403" ]; then
    printf "\nThe session is still open: HTTP %s\n" "${HTTP_CODE}"
    [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}"
