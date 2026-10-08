#!/bin/bash
# ==============================================================================
# Script Name: 01.events_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the events using the `/events` endpoint: the tasks SecureTransport
# is processing right now, such as an Advanced Routing run for a file that has
# arrived. It demonstrates:
# - Counting them
# - Searching by account, with the * wildcard, and by status
# - Only the Advanced Routing ones, with processorType=
# - Only the ones with a heartbeat in the last hour, with lastHeartbeatAfter=
#
# Usage:
# ./01.events_GET.sh [ACCOUNT_PATTERN [STATUS]]
#
#   ACCOUNT_PATTERN  an account name, * matches anything (default *)
#   STATUS           only the events with this status, for example active (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The list is usually empty: an event lives only while a file is being processed.
#   One whose partner does not answer stays for as long as the server waits.
# - Confirmed directly: the answer is {resultSet, result}. An event's id looks like
#   0x000001A114DB4957...; each entry has status, accountName, fullTarget (the file),
#   agentType, processorType, retryCount, arrivalTime and lastHeartbeat.
# - Confirmed directly: a new event is ready while it waits to be taken, then active
#   while it runs; a ready one has no heartbeat yet. status is matched exactly:
#   active finds events, ACTIVE none.
#   A processorType that does not exist is not refused, it just finds nothing.
# - Confirmed directly: arrivalTime, lastHeartbeatAfter and lastHeartbeatBefore are
#   timestamps in milliseconds; a date such as 2026-10-07 answers 400 "For input
#   string".
# - Confirmed directly: a file's arrival can show a short-lived event of its own,
#   processorType DEFAULT, before the Advanced Routing one; processorType= tells them
#   apart.
# - An event can stay active after its transfer has failed. 03.events_operations_POST_delete.sh
#   removes it.
# - Requires `jq`, which prints one event per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there are more than two arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/events"
ACCOUNT_PATTERN="${1:-*}"
STATUS="$2"
if [ "$#" -gt 2 ]; then
    printf "Usage: ./01.events_GET.sh [ACCOUNT_PATTERN [STATUS]]\n"
    exit 2
fi
LINE='"  \(.id)  \(.status)  \(.accountName // "-")  \(.fullTarget // "-")  retries \(.retryCount)"'

# st_get CURL_ARGUMENTS...: a GET of the URL given (with any curl options, such as -G --data-urlencode ...). The answer
# is left in RESPONSE. A status other than 200 ends the script with exit 1, after printing the status and the answer.
st_get() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "$@" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}

printf "Events: "
st_get "${MAIN_URL}?limit=1&fields=id"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

printf "\nThe events of the accounts matching %s: id, status, account, file, retries:\n" "${ACCOUNT_PATTERN}"
STATUS_FILTER=()
[ -n "${STATUS}" ] && STATUS_FILTER=(--data-urlencode "status=${STATUS}")
st_get -G "${MAIN_URL}" --data-urlencode "accountName=${ACCOUNT_PATTERN}" "${STATUS_FILTER[@]}"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"

printf "\nOnly the Advanced Routing ones:\n"
st_get -G "${MAIN_URL}" --data-urlencode "accountName=${ACCOUNT_PATTERN}" --data-urlencode "processorType=ADVANCED_ROUTING"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"

# The last hour, as a timestamp in milliseconds
SINCE=$(( ($(date +%s) - 3600) * 1000 ))
printf "\nWith a heartbeat in the last hour:\n"
st_get -G "${MAIN_URL}" --data-urlencode "accountName=${ACCOUNT_PATTERN}" --data-urlencode "lastHeartbeatAfter=${SINCE}"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"
