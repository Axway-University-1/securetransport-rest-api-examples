#!/bin/bash
# ==============================================================================
# Script Name: 02.transactionManager_operations_POST_stop.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script STOPS the Transaction Manager (TM) of the whole server, using the `/transactionManager/operations`
# endpoint with operation=stop. The Transaction Manager runs the transfers and the routing; with it stopped the server
# takes no more of them. There is NO start operation: it cannot be started again through the API.
# It demonstrates:
# - A graceful stop (the default): the events in progress are processed first, within a timeout in seconds
# - An immediate stop (GRACEFUL false)
# - A guard: nothing is sent unless the first argument is the confirmation word
#
# Usage:
# ./02.transactionManager_operations_POST_stop.sh stop-the-transaction-manager [GRACEFUL [TIMEOUT]]
#
#   stop-the-transaction-manager
#                 the confirmation: this exact word, required. Without it, or with any other
#                 word, the script prints this usage, sends NOTHING and exits 2
#   GRACEFUL      true (default) or false
#   TIMEOUT       seconds to let the events in progress finish, a whole number, only with GRACEFUL true
#                 (optional; the server's TransactionManager.GracefulShutdownTimeout option when left out)
#
# Risk: disruptive - stops the Transaction Manager of the whole server; cannot be undone through the API
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which reads the answer.
# - THIS WAS NOT RUN AGAINST A SERVER. It stops the Transaction Manager of the whole server, and there is no operation to start it
#   again through the API (see below), so no lab was stopped to see the answer. It was written from the reference and from
#   `python/python3/stGraceful.py`, which makes the same call (`operation=stop&graceful=true&timeout=N`, no body), and is tested
#   offline with a stub `curl` that never reaches a server (tests/checks/test_bash_admin_api.sh).
# - Run it only on a server you can restart, to see the answer. What brings the Transaction Manager back is a restart of the
#   server's own services, outside this API. Check it afterwards with 01.transactionManager_GET.sh.
# - Nothing is sent unless the first argument is exactly `stop-the-transaction-manager`. There is no default and no environment variable
#   that stands in for it. The arguments are checked before anything is sent: a bad one exits 2.
# - The reference: `operation` is required and can only be `stop`; `graceful` is a boolean, false when left out (an immediate stop;
#   this script sends it always, and makes true the default); `timeout` is in seconds, and the events it lets finish are the
#   server side transfers, the post processing actions and the advanced routing operations. The answer is 200 with
#   `{"message": ..., "isSuccessful": true or false}`; this script prints both and exits 0 on 200 with isSuccessful not false.
# - Recorded in st-api-gotchas by an earlier session, not repeated here: `operation=start` is refused, 400
#   `stopGracefully.arg1 must match "(?i)(stop)"`. Unlike a daemon, a server or a cluster service, only stop exists.
#   The stop operation itself was NEVER sent to the lab while covering this resource, not even with a wrong value.
# - Exit codes: 0 when the server answered 200 and the stop worked, 1 when it refuses or says it did not work, 2 when the confirmation
#   or an argument is wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/transactionManager"
CONFIRMATION="stop-the-transaction-manager"
USAGE="Usage: 02.transactionManager_operations_POST_stop.sh ${CONFIRMATION} [GRACEFUL [TIMEOUT]]"
GRACEFUL="${2:-true}"
TIMEOUT="$3"

if [ "$1" != "${CONFIRMATION}" ]; then
    printf "This stops the Transaction Manager of the whole server, and it cannot be started again through the API.\n"
    printf "Nothing was sent. To go on, give the word %s as the first argument.\n" "${CONFIRMATION}"
    printf "%s\n" "${USAGE}"
    exit 2
fi
if [ "${GRACEFUL}" != "true" ] && [ "${GRACEFUL}" != "false" ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
case "${TIMEOUT}" in
    *[!0-9]*) printf "%s\n" "${USAGE}"; exit 2 ;;
esac
if [ -n "${TIMEOUT}" ] && [ "${GRACEFUL}" != "true" ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
if [ -n "$4" ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi

URL="${MAIN_URL}/operations?operation=stop&graceful=${GRACEFUL}"
if [ -n "${TIMEOUT}" ]; then
    URL="${URL}&timeout=${TIMEOUT}"
fi

printf "Stopping the Transaction Manager (graceful: %s)...\n" "${GRACEFUL}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${URL}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '.message // .'
if [ "$(printf '%s' "${RESPONSE}" | jq -r '.isSuccessful')" = "false" ]; then
    exit 1
fi
