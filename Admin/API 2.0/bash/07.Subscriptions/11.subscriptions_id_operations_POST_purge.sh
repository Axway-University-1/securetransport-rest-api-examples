#!/bin/bash
# ==============================================================================
# Script Name: 11.subscriptions_id_operations_POST_purge.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script purges a subscription's folder, using the `/subscriptions/{id}/operations`
# endpoint with operation=Purge: the folder and everything in it are removed, and
# the subscription stays.
#
# Usage:
# ./11.subscriptions_id_operations_POST_purge.sh ACCOUNT APPLICATION FOLDER
#
#   ACCOUNT      the account that subscribes
#   APPLICATION  the application it subscribes to
#   FOLDER       the folder of the subscription
#
# Risk: write - deletes the subscription's folder and every file in it
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The subscription is looked up by account, application and folder, and must be the only one
#   that matches. A subscription is addressed by a generated id, and an account may have several
#   on one application as long as their folders differ.
# - This deletes files that cannot be got back. Check the arguments before running it.
# - Confirmed directly: the answer is 204, with no body. The whole folder goes, not only what is in
#   it, and the subscription stays (HEAD is still 200); other folders of the account are not touched.
#   Deleting the subscription with `DELETE /subscriptions/{id}?purge=true` does the same, and without
#   `purge` the folder is left in the account (13.subscriptions_id_DELETE_types.sh uses purge=true).
#   The operation name is case sensitive: `purge` is 404.
# - Requires `jq`, which reads the id.
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
[ -n "${ACCOUNT}" ] && [ -n "${APPLICATION}" ] && [ -n "${FOLDER}" ] || { printf "Usage: ./11.subscriptions_id_operations_POST_purge.sh ACCOUNT APPLICATION FOLDER\n"; exit 2; }

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

printf "Purging the folder '%s' of '%s' (subscription to '%s')...\n" "${FOLDER}" "${ACCOUNT}" "${APPLICATION}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/${SUBSCRIPTION_ID}/operations?operation=Purge" \
  -H "accept: */*" -H "${REFERER_HEADER}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
