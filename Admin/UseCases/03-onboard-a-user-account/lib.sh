#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-28
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, ST_URL, the cookie jar
# session.cookie.jar of this use case and st_session) and gives the helpers the steps share:
#
#   uc_check_name NAME    the account must be named example_*: steps 06 and 99 delete by name, and this keeps them off a real account
#   uc_uid NAME           the same user id every time for the same name (50000 to 59999): a home folder keeps the uid of its first owner
#   EU_URL                the End User API: ST_ENDUSER_PORT when it is set, otherwise the admin port minus one
#   PASSWORD_FILE         state.local.password, the generated password of the account (git ignores it)
#   uc_empty_home NAME PASSWORD   deletes what is in the home folder of the account, through the End User API, and says how much
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

PASSWORD_FILE="${UC_DIR}/state.local.password"
DEFAULT_NAME="example_onboard"
ST_ENDUSER_PORT="${ST_ENDUSER_PORT:-$((ST_PORT - 1))}"
EU_URL="https://${ST_SERVER}:${ST_ENDUSER_PORT}/api/v2.0"

# uc_check_name NAME USAGE: exits 2, with the usage, before anything is sent, when NAME is not a name this use case may touch
uc_check_name() {
    local name="$1" usage="$2"
    if [[ ! "${name}" =~ ^example_[A-Za-z0-9._-]+$ ]]; then
        printf "NAME is '%s': it must start with example_ and hold only letters, digits, '.', '_' and '-'. This use case deletes the account it makes, by name, so it stays off real accounts.\n" "${name}"
        printf "%s\n" "${usage}"
        exit 2
    fi
}

uc_uid() {
    echo $((50000 + $(printf '%s' "$1" | cksum | cut -d' ' -f1) % 9999))
}

# uc_empty_home NAME PASSWORD: lists the home folder of the account as the account, deletes the files and then the folders from the bottom up
uc_empty_home() {
    local name="$1" password="$2" list entries path enc removed=0 code
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
