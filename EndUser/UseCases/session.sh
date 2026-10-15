#!/bin/bash
# ==============================================================================
# Script Name: session.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by the lib.sh of the use cases after 01-authentication. Loads the settings
# of the EndUser examples, names the cookie jar of the use case (session.cookie.jar,
# ignored by git) and gives the two helpers the scripts share:
#
#   st_session   makes sure there is an active session. It tries the cookie jar with a
#                GET of /myself; with no jar, or a 401 or 403, it logs in with Basic
#                authentication (as 01-authentication/03 does) and keeps the new jar.
#   st_enc PATH  encodes a path for a URL, each part of it (spaces, accents) but not the slashes.
#
# The caller sets UC_DIR (the folder of the use case) before sourcing it.
# ==============================================================================

source "${UC_DIR}/../../API 2.0/bash/set_variables.sh"

JAR="${UC_DIR}/session.cookie.jar"
CSRF_FILE="${UC_DIR}/state.local.csrf"
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

st_enc() { printf '%s' "$1" | jq -Rr 'split("/") | map(@uri) | join("/")'; }
