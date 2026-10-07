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
curl -k --cookie-jar cookie.jar -D "${LOGIN_HEADERS}" -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}"

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
curl -k --cookie cookie.jar -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}"

# Log out
curl -k -L --cookie cookie.jar -X DELETE "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}"

# Verify session is terminated
curl -k --cookie cookie.jar -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}"
