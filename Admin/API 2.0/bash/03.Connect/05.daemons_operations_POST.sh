#!/bin/bash
# ==============================================================================
# Script Name: 05.daemons_operations_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script starts or stops a daemon (ftp, http, ssh, as2 or pesit), using the `/daemons/operations` endpoint.
# A stop takes every protocol that daemon serves down with it: its clients are refused until it is started again.
# It demonstrates:
# - A guard: nothing is sent unless the daemon and the operation are given and, for a stop, the confirmation word as well
# - A graceful stop (the default), which lets the connections in progress finish within a timeout, and an immediate one
# - The status of the daemon is printed first, with the command that brings it back
# - The HTTP code, and the result the server gives for each daemon
#
# Usage:
# ./05.daemons_operations_POST.sh DAEMON start
# ./05.daemons_operations_POST.sh DAEMON stop stop-the-DAEMON-daemon [GRACEFUL [TIMEOUT]]
#
#   DAEMON        ftp, http, ssh, as2 or pesit
#   stop-the-DAEMON-daemon
#                 the confirmation of a stop: this exact word, with the daemon's name in it (stop-the-ssh-daemon). Without it, or
#                 with any other word, the script prints this usage, sends NOTHING and exits 2. A start needs none
#   GRACEFUL      true (default) lets the connections in progress finish; false stops at once
#   TIMEOUT       seconds to wait for them, a whole number, only with GRACEFUL true (optional; the daemon's own timeout when left out)
#
# Risk: disruptive - stops and starts daemons: every protocol on them goes down meanwhile
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - THIS STOPS A DAEMON of the whole server. There is no default daemon and no environment variable that stands in for the confirmation word:
#   the daemon and the operation are arguments, and a stop needs `stop-the-DAEMON-daemon` as well. The arguments are checked before anything is sent: a bad one exits 2.
# - It prints the daemon's status first, and the command that undoes the operation. Starting a daemon again with this script is the way back; a protocol server
#   that was running on it may then need its own start (13.servers_operations_POST.sh starts every server and daemon found not running).
# - A graceful stop with a timeout keeps running on the server after this script is gone: never kill the script before it returns, and do not start the daemon again
#   while a delayed stop may still be pending (see st-api-gotchas).
# - THIS WAS NOT RUN against a server while the script was made safe: no daemon of the lab was stopped or started, by this change. What follows is from the reference and from
#   what check 23 recorded earlier (its docstring and st-api-gotchas): the answer is 200 with `daemonOperationResults`, a list of `{daemon, message, isSuccessful}`; a start of the
#   as2 daemon is 200 with `isSuccessful` false and "Can not start AS2 daemon - the default server As2 Default is not enabled." whatever the status code says. This script
#   prints every result and exits 1 when one has `isSuccessful` false, or when the status is not 200. It is tested offline against a stub `curl`.
# - Requires `jq`, which reads the status and the answer.
# - Exit codes: 0 when the server answered 200 and every daemon result is successful, 1 when it refuses or a result is not successful, 2 when an argument is missing or
#   wrong, or the confirmation word of a stop is not given (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons"
DAEMON="$1"
OPERATION="$2"
USAGE="Usage: 05.daemons_operations_POST.sh DAEMON start, or DAEMON stop stop-the-DAEMON-daemon [GRACEFUL [TIMEOUT]]"

case "${DAEMON}" in
    ftp|http|ssh|as2|pesit) ;;
    *) printf "DAEMON is ftp, http, ssh, as2 or pesit. Nothing was sent.\n%s\n" "${USAGE}"; exit 2 ;;
esac
case "${OPERATION}" in
    start)
        if [ "$#" -ne 2 ]; then printf "%s\n" "${USAGE}"; exit 2; fi
        QUERY="operation=start&daemon=${DAEMON}"
        ;;
    stop)
        CONFIRMATION="stop-the-${DAEMON}-daemon"
        if [ "$3" != "${CONFIRMATION}" ]; then
            printf "This stops the %s daemon of the whole server: its clients are refused until it is started again.\n" "${DAEMON}"
            printf "Nothing was sent. To go on, give the word %s as the third argument.\n" "${CONFIRMATION}"
            printf "%s\n" "${USAGE}"
            exit 2
        fi
        GRACEFUL="${4:-true}"
        TIMEOUT="$5"
        if [ "${GRACEFUL}" != "true" ] && [ "${GRACEFUL}" != "false" ]; then printf "%s\n" "${USAGE}"; exit 2; fi
        case "${TIMEOUT}" in *[!0-9]*) printf "%s\n" "${USAGE}"; exit 2 ;; esac
        if [ -n "${TIMEOUT}" ] && [ "${GRACEFUL}" != "true" ]; then printf "%s\n" "${USAGE}"; exit 2; fi
        if [ "$#" -gt 5 ]; then printf "%s\n" "${USAGE}"; exit 2; fi
        QUERY="operation=stop&daemon=${DAEMON}&graceful=${GRACEFUL}"
        if [ -n "${TIMEOUT}" ]; then QUERY="${QUERY}&timeout=${TIMEOUT}"; fi
        ;;
    *) printf "OPERATION is start or stop. Nothing was sent.\n%s\n" "${USAGE}"; exit 2 ;;
esac

printf "Reading the status of the daemons...\n"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the daemons: HTTP %s\n" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
STATUS=$(printf '%s' "${RESPONSE}" | jq -r --arg key "${DAEMON}Status" '.[$key] // "unknown"')
printf "The %s daemon is now: %s\n" "${DAEMON}" "${STATUS}"
if [ "${OPERATION}" = "stop" ]; then
    printf "To bring it back: ./05.daemons_operations_POST.sh %s start\n" "${DAEMON}"
else
    printf "To stop it again: ./05.daemons_operations_POST.sh %s stop stop-the-%s-daemon\n" "${DAEMON}" "${DAEMON}"
fi

printf "Performing '%s' on the '%s' daemon...\n" "${OPERATION}" "${DAEMON}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/operations?${QUERY}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '(.daemonOperationResults // [.])[] | "\(.daemon // "") \(.message // "") (successful: \(.isSuccessful))"'
if [ "$(printf '%s' "${RESPONSE}" | jq '[(.daemonOperationResults // [.])[] | select(.isSuccessful == false)] | length')" != "0" ]; then
    exit 1
fi
