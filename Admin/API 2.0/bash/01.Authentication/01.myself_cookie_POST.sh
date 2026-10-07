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
curl -k --cookie-jar cookie.jar -D "${LOGIN_HEADERS}" -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" \
  -H "accept: application/json" -H "${REFERER_HEADER}"

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
curl -k --cookie cookie.jar -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}"
