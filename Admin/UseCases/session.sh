#!/bin/bash
# ==============================================================================
# Script Name: session.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by the lib.sh of the Admin use cases. Loads the settings of the Admin examples
# (Admin/API 2.0/bash/set_variables.local.sh), builds ST_URL, names the cookie jar
# and the csrfToken, API key and API key id files of the use case (session.cookie.jar and
# state.local.*, ignored by git)
# and gives the one helper the scripts share:
#
#   st_session   makes sure there is an active session. It tries the cookie jar with a GET of
#                /myself; with no jar, or a 401 or 403, it logs in with Basic authentication
#                (as 01-authentication/03 does) and keeps the new jar and the csrfToken.
#
# The caller sets UC_DIR (the folder of the use case) before sourcing it.
# ==============================================================================

source "${ST_ADMIN_LOCAL_VARIABLES:-${UC_DIR}/../../API 2.0/bash/set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }

ST_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"
JAR="${UC_DIR}/session.cookie.jar"
CSRF_FILE="${UC_DIR}/state.local.csrf"
APIKEY_FILE="${UC_DIR}/state.local.apikey"        # an API key, as 08 makes it
APIKEY_ID_FILE="${UC_DIR}/state.local.apikey_id"  # its id, to revoke it
REFERER="THIS_IS_A_RANDOM_TEXT"   # the server wants a Referer header, any text will do

st_session() {
    local code="" headers
    if [ -f "${JAR}" ]; then
        code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself" \
               -H "accept: application/json" -H "Referer: ${REFERER}")
        case "${code}" in
            401|403) echo "The session is no longer active (HTTP ${code}). Logging in..." ;;
            *) return 0 ;;
        esac
    else
        echo "There is no session yet. Logging in..."
    fi
    rm -f "${JAR}" "${CSRF_FILE}"
    headers=$(mktemp)
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -D "${headers}" --cookie-jar "${JAR}" \
           -u "${ST_USER}:${ST_PASSWORD}" -X POST "${ST_URL}/myself" \
           -H "accept: application/json" -H "Referer: ${REFERER}")
    tr -d '\r' < "${headers}" | sed -n 's/^[Cc][Ss][Rr][Ff][Tt]oken: *//p' > "${CSRF_FILE}"
    rm -f "${headers}"
    if [[ "${code}" != 200 ]]; then
        echo "Login failure: HTTP ${code}"
        rm -f "${JAR}" "${CSRF_FILE}"
        exit 1
    fi
}
