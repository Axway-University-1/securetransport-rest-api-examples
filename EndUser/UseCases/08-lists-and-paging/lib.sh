#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, ST_URL, the cookie jar session.cookie.jar of this use case, st_session and st_enc), and gives the helpers the steps share:
#
#   eu_check_number VALUE LABEL USAGE   a whole number of 1 or more; exits 2 with the usage otherwise
#   eu_get PATH [NAME=VALUE ...]        GET /PATH with the query made of the NAME=VALUE pairs, each encoded; sets EU_CODE and EU_BODY
#   eu_why                              prints why the server refused the call in EU_BODY
#   eu_not_allowed                      says what a 403 on /transfers means
#
# What this use case makes: a folder named example_uc_lists in the home folder, and files lst_01.txt, lst_02.txt, ... in it.
# 99.cleanup_DELETE.sh removes exactly these names and nothing else.
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

FOLDER="example_uc_lists"
MAX_FILES=20

eu_check_number() {
    if [[ ! "$1" =~ ^[1-9][0-9]*$ ]]; then
        printf "%s is '%s': it must be a whole number of 1 or more.\n%s\n" "$2" "$1" "$3"
        exit 2
    fi
}

eu_get() {
    local path="$1" param result args=()
    shift
    for param in "$@"; do args+=(--data-urlencode "${param}"); done
    result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -G "${ST_URL}/${path}" "${args[@]}" -H "accept: application/json" -H "Referer: ${REFERER}")
    EU_CODE="${result: -3}"
    EU_BODY="${result%???}"
}

eu_why() {
    printf '%s' "${EU_BODY}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${EU_BODY}"
}

eu_not_allowed() {
    echo "403: the account may not use the transfers web service (transfersWebServiceAllowed in GET /myself; the administrator sets it)."
}
