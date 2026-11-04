#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case, the ones in this folder and the ones in 2.0 and 1.4. Loads ../session.sh (the settings, ST_URL of the API 2.0, the cookie jar session.cookie.jar of
# this use case and st_session) and gives the helpers the steps share:
#
#   uc_get RESOURCE [NAME=VALUE ...]        GET of the API 2.0 with a session, the query made of the NAME=VALUE pairs, each encoded; sets LIST_CODE and LIST_BODY
#   uc_why                                  prints why the server refused the call in LIST_BODY
#   uc_post RESOURCE JSON                   POST of the API 2.0 with a session; on any answer but 201 prints why and returns 1
#   uc_head RESOURCE / uc_delete RESOURCE   the status of a HEAD / of a DELETE of the API 2.0
#   uc14_call METHOD RESOURCE [N=V ...]     a call of the API 1.4 (ST_URL14) with Basic authentication and the query made of the pairs; sets LIST_CODE and LIST_BODY
#   uc_window                               the time at which step 02 started: the transfers of this run are the ones after it (state.local.window)
#   uc_check_account VALUE USAGE            exits 2 with the usage, before any call, when VALUE is not an account name
#
# The objects of this use case are example_rsb_*: two user accounts. example_rsb_a is the one whose transfers the API 2.0 resubmits one by one, example_rsb_b the one whose transfers
# the API 1.4 resubmits with one call. Each uploads UPLOADS files, report_1.txt and so on, with the End User API.
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

ST_URL14="https://${ST_SERVER}:${ST_PORT}/api/v1.4"
ST_ENDUSER_PORT="${ST_ENDUSER_PORT:-$((ST_PORT - 1))}"
EU_URL="https://${ST_SERVER}:${ST_ENDUSER_PORT}/api/v2.0"
PASSWORD_FILE="${UC_DIR}/state.local.password"      # the password of the two accounts (01 writes it, git ignores it)
WINDOW_FILE="${UC_DIR}/state.local.window"          # the time at which 02 started

A20="example_rsb_a"        # resubmitted one by one, with the API 2.0
A14="example_rsb_b"        # resubmitted with one call, with the API 1.4
# The user ids are fixed: a home folder keeps the uid of its first owner, and an account made again with another uid cannot write into it (403).
UC_ACCOUNTS=("${A20} 58301" "${A14} 58302")
UPLOADS=3

uc_get() {
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

uc_post() {      # RESOURCE JSON: any other answer than 201 is a failure with the reason
    local result code
    result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X POST "${ST_URL}/$1" -H "accept: */*" -H "Referer: ${REFERER}" \
             -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "$2")
    code="${result##*$'\n'}"
    if [ "${code}" != "201" ]; then
        printf "POST /%s: HTTP %s\n" "$1" "${code}"
        printf '%s\n' "${result%$'\n'*}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${result%$'\n'*}"
        return 1
    fi
    printf "  HTTP 201\n"
}

uc_head() {      # RESOURCE: the status of a HEAD
    curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ST_URL}/$1" -H "accept: */*" -H "Referer: ${REFERER}"
}

uc_delete() {    # RESOURCE: the status of a DELETE
    curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/$1" -H "accept: application/json" -H "Referer: ${REFERER}" \
        -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
}

uc14_call() {    # METHOD RESOURCE [N=V ...]: the API 1.4, Basic authentication, the pairs are the query
    local method="$1" resource="$2" param result args=()
    shift 2
    for param in "$@"; do args+=(--data-urlencode "${param}"); done
    result=$(curl -k -s -w "%{http_code}" -u "${ST_USER}:${ST_PASSWORD}" -X "${method}" -G "${ST_URL14}/${resource}" "${args[@]}" -H "accept: application/json" -H "Referer: ${REFERER}")
    LIST_CODE="${result: -3}"
    LIST_BODY="${result%???}"
}

# BSD date (macOS) and GNU date (Linux) differ here.
if date -v-1d >/dev/null 2>&1; then
    uc_rfc_seconds_ago() { date -v-"$1"S -R; }
else
    uc_rfc_seconds_ago() { date -d "$1 seconds ago" -R; }
fi

uc_window() {    # the time at which 02 started; empty when 02 has not run
    cat "${WINDOW_FILE}" 2>/dev/null
}

uc_check_account() {  # VALUE USAGE
    if [[ ! "$1" =~ ^[A-Za-z0-9_.][A-Za-z0-9_.-]*$ ]]; then
        printf "ACCOUNT is '%s': an account name (letters, digits, _ . -, not empty, not starting with -).\n%s\n" "$1" "$2"
        exit 2
    fi
}
