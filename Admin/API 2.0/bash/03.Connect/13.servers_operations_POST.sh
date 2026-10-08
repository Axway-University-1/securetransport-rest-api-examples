#!/bin/bash
# ==============================================================================
# Script Name: 13.servers_operations_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script starts or stops a protocol server, using the `/servers/operations` endpoint.
# A stop refuses the clients of that server until it is started again.
# It demonstrates:
# - A guard: nothing is sent unless the server and the operation are given and, for a stop, the confirmation word as well
# - Starting one server, with the status of the server and of its daemon printed first and the command that undoes it
# - Starting every server that is found not running, and then every daemon that is not running (--all-stopped)
# - The HTTP code, and the result the server gives for each server
#
# Usage:
# ./13.servers_operations_POST.sh SERVER start
# ./13.servers_operations_POST.sh SERVER stop stop-the-SERVER-server [TIMEOUT]
# ./13.servers_operations_POST.sh --all-stopped start-all-stopped-servers
#
#   SERVER    the name of the server, as GET /servers lists it ("Ssh Default"): quote it when it has a space
#   stop-the-SERVER-server
#             the confirmation of a stop: this exact word, with the server's name in it (stop-the-Ssh Default-server). Without
#             it, or with any other word, the script prints this usage, sends NOTHING and exits 2. A start needs none
#   TIMEOUT   seconds to wait for the server's answer, a whole number (optional; the reference says 150 or more, and 150 is its default)
#   --all-stopped start-all-stopped-servers
#             starts every server that is not running and then every daemon that is not running: it needs its own word, as it
#             starts what an administrator may have stopped on purpose
#
# Risk: disruptive - stops and starts protocol servers: their clients are refused while one is stopped
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - THIS CAN STOP A SERVER of the whole system. There is no default server and no environment variable that stands in for the
#   confirmation word: the server and the operation are arguments, and a stop needs `stop-the-SERVER-server` as well. The arguments are
#   checked before anything is sent: a bad one exits 2. It used to start every stopped server and daemon when run bare; that is
#   `--all-stopped` now, with its own word.
# - It reads the servers first, prints the server's state and the state of the daemon of its protocol, and the command that undoes the
#   operation. A server that is not there is a stop of nothing: exit 1, no operation sent. A server already in the state asked for (a start
#   of one that is active, a stop of one that is not) is left alone: exit 0, no operation sent.
# - A server needs the daemon of its protocol: when that one is not running the script says so and points at
#   05.daemons_operations_POST.sh, and still sends the start. Starting a server right after its daemon can fail for a moment and
#   succeed on a retry (see st-api-gotchas).
# - `--all-stopped` keeps the order of the older script: the servers first, then the daemons. The as2 server and daemon of a lab
#   that has AS2 disabled cannot start (see below), so on such a lab it ends with exit 1 by design.
# - THIS WAS NOT RUN against a server while the script was made safe: no server of the lab was started or stopped by this change. The
#   status codes and the answer are from the reference and from what check 23 recorded earlier. What WAS confirmed directly, with names
#   that do not exist (nothing started or stopped): the answer is 200 with `{"serverStatuses": [{"serverName", "message", "isSuccessful"}]}`
#   whether or not it worked, so a 200 proves nothing and this script reads `isSuccessful`; an unknown server is 200 with `isSuccessful`
#   false and "Server with name X does not exist."; a start with no `serverName` is 400 "Specify at least one server name to start.";
#   an `operation` that is not start or stop is 400 (`must match "(?i)start|(?i)stop"`: the pattern ignores case, which was not tried). From earlier work: a start of
#   the as2 daemon is 200 with `isSuccessful` false when its default server is not enabled. This script is tested offline against a stub `curl`.
# - Requires `jq`, which reads the state, encodes nothing by hand and builds the output.
# - Exit codes: 0 when the server answered 200 and every result is successful (or there was nothing to do), 1 when it refuses, a
#   result is not successful or the server is not there, 2 when an argument is missing or wrong, or the confirmation word is not
#   given (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"
USAGE="Usage: 13.servers_operations_POST.sh SERVER start, or SERVER stop stop-the-SERVER-server [TIMEOUT], or --all-stopped start-all-stopped-servers"
ALL_WORD="start-all-stopped-servers"

if [ "$1" = "--all-stopped" ]; then
    if [ "$#" -ne 2 ] || [ "$2" != "${ALL_WORD}" ]; then
        printf "This starts every server and daemon that is not running, including those an administrator stopped on purpose.\n"
        printf "Nothing was sent. To go on, give the word %s as the second argument.\n" "${ALL_WORD}"
        printf "%s\n" "${USAGE}"
        exit 2
    fi
    MODE="all"
else
    MODE="one"
    SERVER="$1"
    OPERATION="$2"
    if [ -z "${SERVER}" ]; then
        printf "SERVER is the name of a server (or --all-stopped). Nothing was sent.\n%s\n" "${USAGE}"
        exit 2
    fi
    case "${OPERATION}" in
        start)
            if [ "$#" -ne 2 ]; then printf "%s\n" "${USAGE}"; exit 2; fi
            TIMEOUT=""
            ;;
        stop)
            CONFIRMATION="stop-the-${SERVER}-server"
            if [ "$3" != "${CONFIRMATION}" ]; then
                printf "This stops the server %s: its clients are refused until it is started again.\n" "${SERVER}"
                printf "Nothing was sent. To go on, give the word %s as the third argument.\n" "${CONFIRMATION}"
                printf "%s\n" "${USAGE}"
                exit 2
            fi
            TIMEOUT="$4"
            case "${TIMEOUT}" in *[!0-9]*) printf "TIMEOUT is a whole number of seconds. Nothing was sent.\n%s\n" "${USAGE}"; exit 2 ;; esac
            if [ "$#" -gt 4 ]; then printf "%s\n" "${USAGE}"; exit 2; fi
            ;;
        *) printf "OPERATION is start or stop. Nothing was sent.\n%s\n" "${USAGE}"; exit 2 ;;
    esac
fi

# The answer to a refused call: the server's own messages, or the text as it is
show_error() { printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"; }

# list_servers: every server, as a JSON array of {protocol, serverName, isActive}, in SERVERS_JSON; exits 1 when it cannot
list_servers() {
    local offset=0 page count
    SERVERS_JSON="[]"
    while :; do
        RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/servers" \
          --data-urlencode "fields=serverName,isActive" --data-urlencode "limit=200" --data-urlencode "offset=${offset}" \
          -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
        HTTP_CODE="${RESPONSE##*$'\n'}"
        RESPONSE="${RESPONSE%$'\n'*}"
        if [ "${HTTP_CODE}" != "200" ]; then
            printf "Could not read the servers: HTTP %s\n" "${HTTP_CODE}"
            show_error "${RESPONSE}"
            exit 1
        fi
        page=$(printf '%s' "${RESPONSE}" | jq -c '.result // []')
        SERVERS_JSON=$(jq -cn --argjson a "${SERVERS_JSON}" --argjson b "${page}" '$a + $b')
        count=$(printf '%s' "${page}" | jq 'length')
        if [ "${count}" -lt 200 ]; then break; fi
        offset=$((offset + 200))
    done
}

# read_daemons: the statuses of the daemons, in DAEMONS_JSON; exits 1 when it cannot
read_daemons() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/daemons" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    DAEMONS_JSON="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not read the daemons: HTTP %s\n" "${HTTP_CODE}"
        show_error "${DAEMONS_JSON}"
        exit 1
    fi
}

# server_operation NAME OPERATION [TIMEOUT]: posts it, prints the code and each server's result; returns 1 on any failure
server_operation() {
    local name="$1" operation="$2" timeout="$3" args=() unsuccessful
    args=(--data-urlencode "serverName=${name}" --data-urlencode "operation=${operation}")
    if [ -n "${timeout}" ]; then args+=(--data-urlencode "timeout=${timeout}"); fi
    printf "Performing '%s' on the server '%s'...\n" "${operation}" "${name}"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X POST "${MAIN_URL}/servers/operations" "${args[@]}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "200" ]; then
        show_error "${RESPONSE}"
        return 1
    fi
    if [ "$(printf '%s' "${RESPONSE}" | jq '(.serverStatuses // []) | length' 2>/dev/null)" = "0" ]; then
        printf "The answer has no result for the server:\n%s\n" "${RESPONSE}"
        return 1
    fi
    printf '%s' "${RESPONSE}" | jq -r '.serverStatuses[] | "\(.serverName // "") \(.message // "") (successful: \(.isSuccessful))"'
    unsuccessful=$(printf '%s' "${RESPONSE}" | jq '[.serverStatuses[] | select(.isSuccessful != true)] | length')
    [ "${unsuccessful}" = "0" ]
}

# daemon_start DAEMON: starts a daemon, prints the code and the result; returns 1 on any failure
daemon_start() {
    local daemon="$1"
    printf "Starting the %s daemon...\n" "${daemon}"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X POST "${MAIN_URL}/daemons/operations" \
      --data-urlencode "operation=start" --data-urlencode "daemon=${daemon}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "200" ]; then
        show_error "${RESPONSE}"
        return 1
    fi
    printf '%s' "${RESPONSE}" | jq -r '(.daemonOperationResults // [.])[] | "\(.daemon // "") \(.message // "") (successful: \(.isSuccessful))"'
    [ "$(printf '%s' "${RESPONSE}" | jq '[(.daemonOperationResults // [.])[] | select(.isSuccessful == false)] | length')" = "0" ]
}

FAILED=0

if [ "${MODE}" = "one" ]; then
    printf "Reading the servers...\n"
    list_servers
    ENTRY=$(printf '%s' "${SERVERS_JSON}" | jq -c --arg name "${SERVER}" '[.[] | select(.serverName == $name)] | .[0] // empty')
    if [ -z "${ENTRY}" ]; then
        printf "There is no server named '%s'. No operation was sent.\n" "${SERVER}"
        exit 1
    fi
    PROTOCOL=$(printf '%s' "${ENTRY}" | jq -r '.protocol // "unknown"')
    IS_ACTIVE=$(printf '%s' "${ENTRY}" | jq -r '.isActive')
    read_daemons
    DAEMON_STATUS=$(printf '%s' "${DAEMONS_JSON}" | jq -r --arg key "${PROTOCOL}Status" '.[$key] // "unknown"')
    if [ "${IS_ACTIVE}" = "true" ]; then STATE="active"; else STATE="not active"; fi
    printf "The %s server '%s' is now: %s. Its %s daemon is: %s\n" "${PROTOCOL}" "${SERVER}" "${STATE}" "${PROTOCOL}" "${DAEMON_STATUS}"
    if [ "${OPERATION}" = "stop" ]; then
        printf "To bring it back: ./13.servers_operations_POST.sh '%s' start\n" "${SERVER}"
        if [ "${IS_ACTIVE}" != "true" ]; then
            printf "It is not active: nothing to stop. No operation was sent.\n"
            exit 0
        fi
    else
        printf "To stop it again: ./13.servers_operations_POST.sh '%s' stop 'stop-the-%s-server'\n" "${SERVER}" "${SERVER}"
        if [ "${IS_ACTIVE}" = "true" ]; then
            printf "It is already active: nothing to start. No operation was sent.\n"
            exit 0
        fi
        if [ "${DAEMON_STATUS}" != "Running" ]; then
            printf "The %s daemon is not running, and a server needs it: ./05.daemons_operations_POST.sh %s start\n" "${PROTOCOL}" "${PROTOCOL}"
        fi
    fi
    server_operation "${SERVER}" "${OPERATION}" "${TIMEOUT}" || FAILED=1
    exit "${FAILED}"
fi

# --all-stopped: the servers that are not running, then the daemons that are not running
printf "Getting the list of servers...\n"
list_servers
printf "Found %s servers\n" "$(printf '%s' "${SERVERS_JSON}" | jq 'length')"
while IFS= read -r NAME; do
    printf "Server: %s is not running\n" "${NAME}"
    server_operation "${NAME}" "start" "" || FAILED=1
done < <(printf '%s' "${SERVERS_JSON}" | jq -r '.[] | select(.isActive == false) | .serverName')
printf '%s' "${SERVERS_JSON}" | jq -r '.[] | select(.isActive == true) | "Server: \(.serverName) is running"'

printf "Getting the list of daemons...\n"
read_daemons
printf '%s\n' "${DAEMONS_JSON}"
for DAEMON in ssh as2 pesit ftp http; do
    STATUS=$(printf '%s' "${DAEMONS_JSON}" | jq -r --arg key "${DAEMON}Status" '.[$key] // "unknown"')
    if [ "${STATUS}" = "Not running" ]; then
        daemon_start "${DAEMON}" || FAILED=1
    else
        printf "Daemon %s is %s\n" "${DAEMON}" "${STATUS}"
    fi
done
exit "${FAILED}"
