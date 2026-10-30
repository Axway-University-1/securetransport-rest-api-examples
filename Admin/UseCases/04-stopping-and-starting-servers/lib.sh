#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, ST_URL, the cookie jar
# session.cookie.jar of this use case and st_session) and gives the helpers the steps share:
#
#   uc_check_daemon DAEMON USAGE    DAEMON must be ftp, http, ssh, as2 or pesit; anything else exits 2 with the usage, before a call
#   uc_check_seconds NAME VALUE USAGE   VALUE must be a whole number of seconds; anything else exits 2 with the usage
#   uc_daemon_status DAEMON         the status the server gives for the daemon ("Running", "Not running"), or "unknown" when it cannot be read
#   uc_read_servers                 every server as a JSON array of {protocol, serverName, isActive}, in SERVERS_JSON; returns 1 when it cannot
#   uc_results                      reads the answer of an operation (a list, or an object that holds one) on standard input, prints one line for each result
#   uc_all_successful               the same input: exit 0 when there is a result and every one says isSuccessful true
#   uc_wait_daemon DAEMON STATE SECONDS   polls until the daemon says STATE, prints how long it took; returns 1 when it does not in time
#   uc_wanted_servers DAEMON        the servers of that protocol this use case waits for: the ones that were active when 01 saved them (all of them when there is no saved copy)
#   uc_wait_servers DAEMON SECONDS  polls until every wanted server is active; returns 1 when one is not in time
#   uc_start_inactive_servers DAEMON   starts, with POST /servers/operations, each wanted server that is not active, and reads isSuccessful; returns 1 on a failure
#
#   DAEMONS_STATE, SERVERS_STATE    state.local.daemons.json and state.local.servers.json: what 01 saved, to compare with and to put back (git ignores them)
#
# Usage:
# source lib.sh
#
# Risk: none
#
# Notes:
# - A wait takes the larger of two times: the clock (date +%s) and POLL seconds for each poll made. On a real server the clock is the larger (each poll is a call as well as a sleep).
#   With the sleep and the clock stubbed, as the offline tests do, the count still ends a loop that would never end.
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

DEFAULT_DAEMON="ftp"
DAEMONS_STATE="${UC_DIR}/state.local.daemons.json"
SERVERS_STATE="${UC_DIR}/state.local.servers.json"
POLL=3

uc_check_daemon() {
    case "$1" in
        ftp|http|ssh|as2|pesit) ;;
        *) printf "DAEMON is '%s': it must be ftp, http, ssh, as2 or pesit. Nothing was sent.\n%s\n" "$1" "$2"; exit 2 ;;
    esac
}

uc_check_seconds() {
    case "$2" in
        ''|*[!0-9]*) printf "%s is '%s': it must be a whole number of seconds. Nothing was sent.\n%s\n" "$1" "$2" "$3"; exit 2 ;;
    esac
}

uc_daemon_status() {
    local result code
    result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/daemons" -H "accept: application/json" -H "Referer: ${REFERER}")
    code=${result: -3}
    if [ "${code}" != "200" ]; then echo "unknown"; return 0; fi
    printf '%s' "${result%???}" | jq -r --arg key "$1Status" '.[$key] // "unknown"' 2>/dev/null || echo "unknown"
}

uc_read_servers() {
    local result code
    result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -G -X GET "${ST_URL}/servers" --data-urlencode "fields=serverName,isActive" --data-urlencode "limit=1000" \
             -H "accept: application/json" -H "Referer: ${REFERER}")
    code=${result: -3}
    if [ "${code}" != "200" ]; then
        printf "Could not read the servers: HTTP %s\n" "${code}"
        return 1
    fi
    SERVERS_JSON=$(printf '%s' "${result%???}" | jq -c '[(.result // [])[] | {protocol, serverName, isActive}]' 2>/dev/null) || { echo "The servers answer could not be read."; return 1; }
}

uc_results() {
    jq -r '(if type == "array" then . else (.daemonOperationResults // .serverStatuses // [.]) end)[] | "  \(.daemon // .serverName // "?"): \(.message // "no message") (isSuccessful: \(.isSuccessful))"'
}

uc_all_successful() {
    [ "$(jq '[(if type == "array" then . else (.daemonOperationResults // .serverStatuses // [.]) end)[]] | (length > 0) and all(.isSuccessful == true)' 2>/dev/null)" = "true" ]
}

uc_wait_daemon() {
    local daemon="$1" state="$2" limit="$3" waited=0 status="" started counted=0
    started=$(date +%s)
    while :; do
        status=$(uc_daemon_status "${daemon}")
        waited=$(($(date +%s) - started))
        [ "${waited}" -ge "${counted}" ] || waited=${counted}
        if [ "${status}" = "${state}" ]; then
            printf "The %s daemon says %s, after about %s seconds.\n" "${daemon}" "${state}" "${waited}"
            return 0
        fi
        [ "${waited}" -lt "${limit}" ] || break
        sleep "${POLL}"
        counted=$((counted + POLL))
    done
    printf "The %s daemon is not '%s' after %s seconds (last status: %s).\n" "${daemon}" "${state}" "${limit}" "${status}"
    return 1
}

uc_wanted_servers() {
    if [ -s "${SERVERS_STATE}" ]; then
        jq -c --arg d "$1" --slurpfile saved "${SERVERS_STATE}" \
           '[.[] | select(.protocol == $d and (.serverName as $n | any($saved[0][]; .serverName == $n and .isActive == true)))]' <<< "${SERVERS_JSON}"
    else
        jq -c --arg d "$1" '[.[] | select(.protocol == $d)]' <<< "${SERVERS_JSON}"
    fi
}

uc_wait_servers() {
    local daemon="$1" limit="$2" waited=0 wanted pending started counted=0 read_ok
    started=$(date +%s)
    while :; do
        uc_read_servers && read_ok=1 || read_ok=0
        waited=$(($(date +%s) - started))
        [ "${waited}" -ge "${counted}" ] || waited=${counted}
        if [ "${read_ok}" = "1" ]; then
            wanted=$(uc_wanted_servers "${daemon}")
            if [ "$(jq 'length' <<< "${wanted}")" = "0" ]; then
                printf "No %s server was active at the start: there is nothing to wait for.\n" "${daemon}"
                return 0
            fi
            pending=$(jq -r '[.[] | select(.isActive != true) | .serverName] | join(", ")' <<< "${wanted}")
            if [ -z "${pending}" ]; then
                printf "The %s servers (%s) are active, after about %s seconds.\n" "${daemon}" "$(jq -r 'map(.serverName) | join(", ")' <<< "${wanted}")" "${waited}"
                return 0
            fi
        fi
        [ "${waited}" -lt "${limit}" ] || break
        sleep "${POLL}"
        counted=$((counted + POLL))
    done
    printf "Not active after %s seconds: %s\n" "${limit}" "${pending:-the servers could not be read}"
    return 1
}

uc_start_inactive_servers() {
    local name result code rc=0
    uc_read_servers || return 1
    while IFS= read -r name; do
        [ -n "${name}" ] || continue
        printf "Starting the server %s...\n" "${name}"
        result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -G -X POST "${ST_URL}/servers/operations" --data-urlencode "serverName=${name}" --data-urlencode "operation=start" \
                 -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
        code=${result##*$'\n'}
        result=${result%$'\n'*}
        printf "HTTP %s\n" "${code}"
        if [ "${code}" != "200" ]; then printf '%s\n' "${result}"; rc=1; continue; fi
        printf '%s' "${result}" | uc_results
        printf '%s' "${result}" | uc_all_successful || rc=1
    done < <(uc_wanted_servers "$1" | jq -r '.[] | select(.isActive != true) | .serverName')
    return ${rc}
}
