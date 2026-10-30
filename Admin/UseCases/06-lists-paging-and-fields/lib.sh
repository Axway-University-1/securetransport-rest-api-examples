#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, ST_URL, the cookie jar session.cookie.jar of this use case and st_session) and gives the helpers the steps share:
#
#   uc_check_resource RESOURCE USAGE        the path of a resource (accounts, logs/transfers): letters, digits, '/', '_' and '-'; exits 2 with the usage otherwise
#   uc_check_number VALUE LABEL USAGE       a whole number of 1 or more; exits 2 with the usage otherwise
#   uc_list RESOURCE [NAME=VALUE ...]       GET /RESOURCE with the query made of the NAME=VALUE pairs, each encoded; sets LIST_CODE and LIST_BODY
#   uc_why                                  prints why the server refused the call in LIST_BODY
#   uc_name N                               the name of the Nth throwaway object: example_lst_N
#
# The objects this use case makes are business units named example_lst_1 to example_lst_9 (a business unit needs only a name and
# a base folder, and makes no folder). Steps 05 and 99 touch these names and no others.
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

PREFIX="example_lst"
MAX_OBJECTS=9

uc_check_resource() {
    if [[ ! "$1" =~ ^[A-Za-z][A-Za-z0-9/_-]*$ ]]; then
        printf "RESOURCE is '%s': it is the path of a resource, such as accounts or logs/transfers (letters, digits, '/', '_' and '-').\n%s\n" "$1" "$2"
        exit 2
    fi
}

uc_check_number() {
    if [[ ! "$1" =~ ^[1-9][0-9]*$ ]]; then
        printf "%s is '%s': it must be a whole number of 1 or more. (0 is not 'all': the server takes it for its default page.)\n%s\n" "$2" "$1" "$3"
        exit 2
    fi
}

uc_list() {
    local resource="$1" param result args=()
    shift
    for param in "$@"; do args+=(--data-urlencode "${param}"); done
    result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -G "${ST_URL}/${resource}" "${args[@]}" -H "accept: application/json" -H "Referer: ${REFERER}")
    LIST_CODE="${result: -3}"
    LIST_BODY="${result%???}"
}

uc_why() {
    printf '%s' "${LIST_BODY}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${LIST_BODY}"
}

uc_name() { echo "${PREFIX}_$1"; }
