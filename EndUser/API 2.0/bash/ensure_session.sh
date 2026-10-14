#!/bin/bash
# ==============================================================================
# Script Name: ensure_session.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by the EndUser examples that need a session. It checks that the session
# in the cookie jar (myCookie.jar) is still active, with a GET of /myself. If it
# is, the example carries on. If there is no cookie jar, or the server refuses the
# session (401 or 403, for example because it has expired), it says so and runs
# 01.Authenticate/01.myself_POST.sh to log in, and then the example carries on.
#
# Usage:
# Source it after set_variables.sh and after COOKIE is set, then call the function:
#
#   source "${SCRIPT_DIR}/../ensure_session.sh"
#   st_ensure_session
#
# Notes:
# - Any other answer to the check (the server unreachable, a 500) is not taken for a
#   lost session: the example carries on, and its own call reports what is wrong.
# - If the login fails, the example stops with exit 1, before it sends anything else.
# - 01.Authenticate/01.myself_POST.sh and 02.myself_DELETE.sh do not use it, and nor do
#   the two examples that log in and out on their own (02.Files/02 and 08), or the
#   password reset ones (03.Myself/04 and 05), which need no session.
# ==============================================================================

EU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

st_ensure_session() {
    local cookie="${COOKIE:-${EU_DIR}/myCookie.jar}" code="" reason

    if [ -f "${cookie}" ]; then
        code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${cookie}" -X GET "${ST_URL}/myself" \
               -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT")
        case "${code}" in
            401|403) reason="The session in myCookie.jar is no longer active (HTTP ${code})" ;;
            *) return 0 ;;
        esac
    else
        reason="There is no session (no myCookie.jar)"
    fi

    printf "\n%s. Logging in first, with 01.Authenticate/01.myself_POST.sh...\n\n" "${reason}"
    if ! bash "${EU_DIR}/01.Authenticate/01.myself_POST.sh"; then
        printf "\nThe login failed, so this example cannot continue.\n"
        exit 1
    fi
    printf "\n"
}
