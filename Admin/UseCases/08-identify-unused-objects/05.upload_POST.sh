#!/bin/bash
# ==============================================================================
# Script Name: 05.upload_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Step 5, the experiment: run a transfer through the composite route example_unu_comp_used, and see what the server log says about each of its routes. The account a1 uploads a small file to the folder of its subscription (/example_unu_in) on the End User API.
# The subscription starts the composite route, which runs its enabled steps: example_unu_rt_on and example_unu_rt_old. The third step is disabled and does not run. Then the script waits for the server log to name the two routes that ran, and shows the entries.
#
# Usage:
# ./05.upload_POST.sh [SECONDS]
#
#   SECONDS  how long to wait for the log entries (default 60)
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/04.FileOperations/03.fileOperations_id_PUT_chunked.sh (the two calls of an upload: declare it with POST /fileOperations, then PUT the content) and Admin/API 2.0/bash/28.ServerLogs/01.logs_server_GET.sh (the search of the log by text).
# - The End User API port is ST_ENDUSER_PORT (set it in set_variables.local.sh when it is not the admin port minus one).
# - What the log says (tried on 5.5-20260924): the entries name the COMPOSITE route ("[example_unu_comp_used]") and never the simple routes by name. A simple route that ran appears by its ID: the step "Sandbox environment {.../<id of the simple route>} used for route
#   execution" (AR0011), and "Step {Compress} with id {<id of the step>} is starting" (AR0108) names the id of its step. A route that a DISABLED step would have run leaves no trace at all, not even a line that says it was skipped. The search is therefore by id, not by name.
# - Every search of the log is itself logged ("GET request for the following resource: /api/v2.0/logs/server?message=<text>..."), and that entry holds the text that was searched. An entry like that is the search, not the route, and does not count.
# - The entries are there within a second or two; the script waits up to SECONDS.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./05.upload_POST.sh [SECONDS]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: SECONDS.\n%s\n" "$#" "${USAGE}"; exit 2; fi
WAIT="${1:-60}"
if [[ ! "${WAIT}" =~ ^[1-9][0-9]*$ ]]; then printf "SECONDS is '%s': a whole number of 1 or more.\n%s\n" "${WAIT}" "${USAGE}"; exit 2; fi
[ -s "${PASSWORD_FILE}" ] || { echo "There is no password for ${A1}: run 01.accounts_certificates_POST.sh first."; exit 1; }
st_session

ON_ID=$(uc_id_of routes "${RT_ON}"); OLD_ID=$(uc_id_of routes "${RT_OLD}"); NEVER_ID=$(uc_id_of routes "${RT_NEVER}")
if [ -z "${ON_ID}" ] || [ -z "${OLD_ID}" ] || [ -z "${NEVER_ID}" ]; then echo "The simple routes are not on the server. Run 04.routes_POST.sh first."; exit 1; fi

PASSWORD=$(cat "${PASSWORD_FILE}")
FILE="hello_$(date +%s).txt"
echo "Declaring the upload of ${SUB_FOLDER}/${FILE} as ${A1}..."
RESULT=$(curl -k -s -w "\n%{http_code}" -u "${A1}:${PASSWORD}" -X POST "${EU_URL}/fileOperations" -H "accept: application/json" -H "Referer: ${REFERER}" \
         -H "Content-Type: application/json" -d "$(jq -cn --arg path "${SUB_FOLDER}/${FILE}" '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')")
CODE="${RESULT##*$'\n'}"
OPERATION=$(printf '%s' "${RESULT%$'\n'*}" | jq -r '.id // empty' 2>/dev/null)
if [ "${CODE}" = "000" ]; then
    echo "No answer from ${ST_SERVER}:${ST_ENDUSER_PORT}. The End User API has its own port: set ST_ENDUSER_PORT in set_variables.local.sh."
    exit 1
fi
if [ "${CODE}" != "200" ] && [ "${CODE}" != "201" ] || [ -z "${OPERATION}" ]; then
    echo "POST /fileOperations: HTTP ${CODE}: no operation id came back, so nothing was uploaded."
    printf '%s\n' "${RESULT%$'\n'*}" | jq -r '(.message // empty)' 2>/dev/null
    exit 1
fi
CONTENT=$(mktemp)
trap 'rm -f "${CONTENT}"' EXIT
printf 'a file that the subscription of %s receives\n' "${A1}" > "${CONTENT}"
CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -u "${A1}:${PASSWORD}" -X PUT "${EU_URL}/fileOperations/${OPERATION}" \
       -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/octet-stream" --data-binary "@${CONTENT}")
if [ "${CODE}" != "200" ] && [ "${CODE}" != "201" ] && [ "${CODE}" != "204" ]; then
    echo "PUT /fileOperations/${OPERATION}: HTTP ${CODE}: the content was refused."
    exit 1
fi
echo "Uploaded (HTTP ${CODE}). Waiting up to ${WAIT} s for the server log to name the routes that ran..."

# entries NAME ID: how many entries of the server log hold the id, without the administrator's own requests (they hold the text searched)
entries() {
    uc_get logs/server "message=$1" "limit=100"
    [ "${LIST_CODE}" = "200" ] || { echo 0; return; }
    printf '%s' "${LIST_BODY}" | jq -r '[(.result // [])[] | select((.message // "") | contains("/api/v2.0/") | not)] | length'
}
START=$(date +%s)
while :; do
    N_ON=$(entries "${ON_ID}"); N_OLD=$(entries "${OLD_ID}")
    if [ "${N_ON}" -gt 0 ] && [ "${N_OLD}" -gt 0 ]; then break; fi
    if [ $(( $(date +%s) - START )) -ge "${WAIT}" ]; then
        echo "After ${WAIT} s the server log names ${RT_ON} in ${N_ON} entries and ${RT_OLD} in ${N_OLD}. Is the subscription ${SUB_FOLDER} started by ${COMP_USED}? Is the route engine running?"
        exit 1
    fi
    sleep 2
done
echo "The log has them, $(( $(date +%s) - START )) s after the upload."

show() {    # NAME ID
    uc_get logs/server "message=$2" "limit=100"
    printf "%s (id %s): %s entries that name it\n" "$1" "$2" "$(printf '%s' "${LIST_BODY}" | jq -r '[(.result // [])[] | select((.message // "") | contains("/api/v2.0/") | not)] | length')"
    printf '%s' "${LIST_BODY}" | jq -r '[(.result // [])[] | select((.message // "") | contains("/api/v2.0/") | not)] | sort_by(.time)[] | "    \(.time)  \(.message[0:150])"'
    printf "    (and %s entries that are only the administrator's own requests for this search)\n" "$(printf '%s' "${LIST_BODY}" | jq -r '[(.result // [])[] | select((.message // "") | contains("/api/v2.0/"))] | length')"
}
show "${RT_ON}" "${ON_ID}"
show "${RT_OLD}" "${OLD_ID}"
show "${RT_NEVER}" "${NEVER_ID}"
echo "The route that a disabled step runs, ${RT_NEVER}, has no entry that names it: the log does not say that a route was skipped."
