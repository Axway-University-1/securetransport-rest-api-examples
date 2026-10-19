#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads the settings of the EndUser
# examples (EndUser/API 2.0/bash/set_variables.local.sh), and names
# the two files this use case keeps between scripts: the cookie jar of its own
# session (session.cookie.jar) and the csrfToken the login returned
# (state.local.csrf). Both are ignored by git, and 99.cleanup_DELETE.sh removes them.
# It does not touch myCookie.jar, the jar of the reference examples.
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ST_ENDUSER_LOCAL_VARIABLES:-${UC_DIR}/../../API 2.0/bash/set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }
export ST_URL="${ST_URL:-https://${ST_SERVER}:${ST_PORT}/api/v2.0}"

JAR="${UC_DIR}/session.cookie.jar"
CSRF_FILE="${UC_DIR}/state.local.csrf"
REFERER="THIS_IS_A_RANDOM_TEXT"   # the server wants a Referer header, any text will do

# st_need_session: stop with a hint when 03 has not been run
st_need_session() {
    if [ ! -f "${JAR}" ]; then
        echo "There is no session yet: run 03.session_login_POST.sh first (or 00.run_all.sh)."
        exit 2
    fi
}
