#!/bin/bash
# ==============================================================================
# Script Name: 10.subscriptions_id_operations_POST_clearPullHistory.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script clears the pull history of a subscription, using the
# `/subscriptions/{id}/operations` endpoint with operation=ClearPullHistory. A
# subscription that keeps a pull history does not pull a file twice; once the
# history is cleared, the next pull fetches the files again.
#
# Usage:
# ./10.subscriptions_id_operations_POST_clearPullHistory.sh ACCOUNT APPLICATION FOLDER
#
#   ACCOUNT      the account that subscribes
#   APPLICATION  the application it subscribes to
#   FOLDER       the folder of the subscription
#
# Risk: write - forgets which files were pulled, so the next pull fetches them again
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The subscription is looked up by account, application and folder, and must be the only one
#   that matches. A subscription is addressed by a generated id, and an account may have several
#   on one application as long as their folders differ.
# - The pull history is kept only when the subscription's fileRetentionPeriod is more than 0
#   (set it with a PUT, 07.subscriptions_id_PUT.sh shows how; it needs an SFTP pull site).
# - It answers 202 and clears in the background: the message says the clearing was submitted.
# - Confirmed directly: with a retention of 5 days, a file pulled and then deleted from the folder was
#   not pulled by the next Pull (09.subscriptions_id_operations_POST_pull.sh), and was pulled again
#   after ClearPullHistory. On a subscription with no history the call is 202 as well.
#   The operation takes an optional body `{"type":"clearPullHistory","fileRetentionPeriod":N}`
#   (0 to 36500, else 400); it was accepted, and what it changes was not seen, so this script sends
#   none. The operation name is case sensitive: `clearpullhistory` and unknown ones are 404.
# - Requires `jq`, which reads the id and prints the message.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions"
ACCOUNT="$1"
APPLICATION="$2"
FOLDER="$3"
[ -n "${ACCOUNT}" ] && [ -n "${APPLICATION}" ] && [ -n "${FOLDER}" ] || { printf "Usage: ./10.subscriptions_id_operations_POST_clearPullHistory.sh ACCOUNT APPLICATION FOLDER\n"; exit 2; }

# The one subscription of that account on that application and folder: "1 <id>",
# or how many there are. The account and application filters are exact; the
# application and the folder are compared again here, on what comes back.
read -r FOUND SUBSCRIPTION_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
  --data-urlencode "account=${ACCOUNT}" --data-urlencode "application=${APPLICATION}" --data-urlencode "fields=id,application,folder" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg application "${APPLICATION}" --arg folder "${FOLDER}" \
    '[(.result // [])[] | select(.application == $application and .folder == $folder)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s subscriptions of the account %s on the application %s and the folder %s; this script acts on exactly one.\n" "${FOUND:-0}" "${ACCOUNT}" "${APPLICATION}" "${FOLDER}"
    exit 1
fi

printf "Clearing the pull history of the subscription of '%s' on '%s', folder '%s'...\n" "${ACCOUNT}" "${APPLICATION}" "${FOLDER}"
RESPONSE=$(curl -s -w "\n%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/${SUBSCRIPTION_ID}/operations?operation=ClearPullHistory" \
  -H "accept: application/json" -H "${REFERER_HEADER}")
HTTP_CODE=${RESPONSE##*$'\n'}
RESULT=${RESPONSE%$'\n'*}
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" = "202" ]; then
    printf '%s' "${RESULT}" | jq -r '.message'
else
    printf "%s\n" "${RESULT}"
    exit 1
fi
