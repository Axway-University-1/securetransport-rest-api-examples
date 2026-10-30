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
#   uc_get RESOURCE [NAME=VALUE ...]      GET /RESOURCE with the query made of the NAME=VALUE pairs, each encoded; sets LIST_CODE and LIST_BODY
#   uc_why                                prints why the server refused the call in LIST_BODY
#   uc_count LABEL RESOURCE [N=V ...]     COUNT = resultSet.totalCount of the call (never returnCount); on a refusal prints LABEL, the code and the reason and returns 1
#   uc_midnight N                         midnight N days ago (negative: ahead) in RFC 2822, asked of date for each day: a day is not always 86400 seconds
#   uc_ddmmyyyy_ago N                     the day N days ago as dd/MM/yyyy, the form of generateReport
#   uc_rfc_seconds_ago S                  the time S seconds ago in RFC 2822
#   uc_check_days / uc_check_date / uc_check_day / uc_check_window / uc_check_bu   each exits 2 with the usage, before any call, when a parameter is wrong
#   uc_empty_home NAME PASSWORD           deletes what is in the home folder of an account through the End User API, and says how much
#
# The objects of the second part are example_use_*: three business units (example_use_bu1 to bu3), two accounts in each (a1 and b1, c1 and d1, e1 and f1), and the number of files each account
# uploads: 25 and 15, 20 and 15, 15 and 10, which makes 100 inbound transfers, 40 for the first unit, 35 for the second and 25 for the third. Steps 06, 07 and 99 touch these names and no others.
#
#   UC_BUS            the three units;  UC_ACCOUNTS  one line for each account: "NAME UNIT UID GID UPLOADS";  UC_TOTAL  the 100 transfers
#   uc_bu_uploads BU  how many transfers the accounts of that unit make
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

PASSWORD_FILE="${UC_DIR}/state.local.password"      # the password of the three accounts (06 writes it, git ignores it)
WINDOW_FILE="${UC_DIR}/state.local.window"          # the time at which 07 started: the transfers of this run are the ones after it
ST_ENDUSER_PORT="${ST_ENDUSER_PORT:-$((ST_PORT - 1))}"
EU_URL="https://${ST_SERVER}:${ST_ENDUSER_PORT}/api/v2.0"
BU1="example_use_bu1"
BU2="example_use_bu2"
BU3="example_use_bu3"
UC_BUS=("${BU1}" "${BU2}" "${BU3}")
# The user ids are fixed: a home folder keeps the uid of its first owner, and an account made again with another uid cannot write into it (403). The group of a unit is the group of its accounts.
UC_ACCOUNTS=("example_use_a1 ${BU1} 57101 57101 25" "example_use_b1 ${BU1} 57201 57101 15"
             "example_use_c1 ${BU2} 56405 56405 20" "example_use_d1 ${BU2} 57401 56405 15"
             "example_use_e1 ${BU3} 57501 57501 15" "example_use_f1 ${BU3} 57601 57501 10")
UC_TOTAL=100
REPORT_FILE="${UC_DIR}/state.local.report"           # the day and ST.Transfers of the report before 07 made its transfers

uc_bu_uploads() {      # BU: the transfers the accounts of that unit make
    local line total=0 name bu uid gid uploads
    for line in "${UC_ACCOUNTS[@]}"; do
        read -r name bu uid gid uploads <<< "${line}"
        [ "${bu}" = "$1" ] && total=$((total + uploads))
    done
    echo "${total}"
}

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

uc_count() {
    local label="$1"
    shift
    uc_get "$@"
    COUNT=""
    if [ "${LIST_CODE}" != "200" ]; then
        printf "%s: HTTP %s: %s\n" "${label}" "${LIST_CODE}" "$(uc_why)"
        return 1
    fi
    COUNT=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount // empty' 2>/dev/null)
    if [[ ! "${COUNT}" =~ ^[0-9]+$ ]]; then
        printf "%s: the answer has no resultSet.totalCount, so there is nothing to count.\n" "${label}"
        COUNT=""
        return 1
    fi
}

# BSD date (macOS) and GNU date (Linux) differ here. The midnight is asked of date for each day, not worked out as N * 86400 seconds: the day a clock changes has 23 or 25 hours.
if date -v-1d >/dev/null 2>&1; then
    uc_midnight() { if [ "$1" -ge 0 ]; then date -v-"$1"d -v0H -v0M -v0S -R; else date -v+"$((-$1))"d -v0H -v0M -v0S -R; fi; }
    uc_ddmmyyyy_ago() { if [ "$1" -ge 0 ]; then date -v-"$1"d +%d/%m/%Y; else date -v+"$((-$1))"d +%d/%m/%Y; fi; }
    uc_rfc_seconds_ago() { date -v-"$1"S -R; }
else
    uc_midnight() { date -d "$1 days ago 00:00:00" -R; }
    uc_ddmmyyyy_ago() { date -d "$1 days ago" +%d/%m/%Y; }
    uc_rfc_seconds_ago() { date -d "$1 seconds ago" -R; }
fi

uc_check_days() {      # VALUE USAGE
    if [[ ! "$1" =~ ^[1-9][0-9]*$ ]]; then
        printf "DAYS is '%s': it must be a whole number of 1 or more.\n%s\n" "$1" "$2"
        exit 2
    fi
}

uc_check_date() {      # VALUE LABEL USAGE
    if [[ ! "$1" =~ ^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$ ]]; then
        printf "%s is '%s': a day written dd/MM/yyyy, the only form generateReport takes (for example 24/10/2026).\n%s\n" "$2" "$1" "$3"
        exit 2
    fi
}

uc_check_day() {       # VALUE USAGE
    if [[ ! "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        printf "DAY is '%s': a day written yyyy-MM-dd, the form the activeUsers filters take (for example 2026-10-24).\n%s\n" "$1" "$2"
        exit 2
    fi
}

uc_check_window() {    # VALUE USAGE
    if [[ ! "$1" =~ ^[A-Z][a-z]{2},\ [0-9]{2}\ [A-Z][a-z]{2}\ [0-9]{4}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ [+-][0-9]{4}$ ]]; then
        printf "FROM is '%s': a time in RFC 2822 with its offset, for example 'Fri, 30 Oct 2026 09:30:00 +0200' (between quotes: it holds spaces).\n%s\n" "$1" "$2"
        exit 2
    fi
}

uc_check_bu() {        # VALUE USAGE
    if [ -z "$1" ] || [[ "$1" == -* ]]; then
        printf "BU is '%s': it is the name of a business unit (not empty, not starting with '-').\n%s\n" "$1" "$2"
        exit 2
    fi
}

# uc_empty_home NAME PASSWORD: lists the home folder of the account as the account, deletes the files and then the folders from the bottom up
uc_empty_home() {
    local name="$1" password="$2" list path enc removed=0 code
    list=$(mktemp)
    uc_walk() {
        local dir="$1" body kind file enc
        if [ -n "${dir}" ]; then
            enc=$(printf '%s' "${dir}" | jq -Rr 'split("/") | map(@uri) | join("/")')
            body=$(curl -k -s -u "${name}:${password}" -G "${EU_URL}/files/${enc}" -H "accept: application/json" -H "Referer: ${REFERER}")
        else
            body=$(curl -k -s -u "${name}:${password}" -G "${EU_URL}/files" -H "accept: application/json" -H "Referer: ${REFERER}")
        fi
        while IFS=$'\t' read -r kind file; do
            [ -n "${file}" ] || continue
            if [ "${kind}" = "dir" ]; then uc_walk "${dir:+${dir}/}${file}"; fi
            printf '%s\n' "${dir:+${dir}/}${file}" >> "${list}"
        done < <(printf '%s' "${body}" | jq -r '(.files // [])[] | [(if .isDirectory then "dir" else "file" end), .fileName] | @tsv' 2>/dev/null)
    }
    uc_walk ""
    while IFS= read -r path; do
        enc=$(printf '%s' "${path}" | jq -Rr 'split("/") | map(@uri) | join("/")')
        code=$(curl -k -s -o /dev/null -w "%{http_code}" -u "${name}:${password}" -X DELETE "${EU_URL}/files/${enc}" -H "accept: application/json" -H "Referer: ${REFERER}")
        case "${code}" in 200|204) removed=$((removed + 1)) ;; *) printf "  could not delete %s (HTTP %s)\n" "${path}" "${code}" ;; esac
    done < "${list}"
    rm -f "${list}"
    printf "Emptied the home folder of %s: %s entries removed.\n" "${name}" "${removed}"
}
