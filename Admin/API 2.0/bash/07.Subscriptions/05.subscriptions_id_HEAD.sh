#!/bin/bash
# ==============================================================================
# Script Name: 05.subscriptions_id_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a subscription exists, using the `/subscriptions/{id}`
# endpoint with HEAD: 200 when it does, 404 when it does not. The path takes the
# subscription's id, so the script looks the id up by account, application and
# folder first.
#
# Usage:
# ./05.subscriptions_id_HEAD.sh [ACCOUNT [APPLICATION [FOLDER]]]
#
#   ACCOUNT      the account that subscribes (default john)
#   APPLICATION  the application it subscribes to (default AdvancedRoutingApplication)
#   FOLDER       the folder of the subscription (default /inbox, which
#                02.subscriptions_POST.sh creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The subscription is looked up by account, application and folder, and must be the only one
#   that matches. A subscription is addressed by a generated id, and an account may have several
#   on one application as long as their folders differ.
# - Confirmed directly: HEAD answers 200 for a subscription of any type and 404, with no body,
#   for an id that does not exist. The `account=` and `application=` filters are exact: case
#   sensitive, with no * wildcard (`EXAMPLE_X` and `example_*` find nothing). `folder=` takes a *.
#   A second subscription on the same application and folder is 400 "All subscriptions to an
#   application should have a unique anchor"; a different folder is fine, so one account has
#   several subscriptions on one application. `type=` with a value that is not a type finds
#   nothing (no error), `limit=-1` is 400 "The limit should be a positive number or 0.".
# - The list is not stable: a call can come back without a subscription that exists, so a
#   "Found 0" is worth one more try before concluding it is not there.
# - Requires `jq`, which reads the id.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions"
ACCOUNT="${1:-john}"
APPLICATION="${2:-AdvancedRoutingApplication}"
FOLDER="${3:-/inbox}"

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

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${SUBSCRIPTION_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The subscription of %s on %s, folder %s, exists, id %s.\n" "${ACCOUNT}" "${APPLICATION}" "${FOLDER}" "${SUBSCRIPTION_ID}"
else
    printf "The subscription of %s on %s, folder %s, id %s, does not exist (HTTP %s).\n" "${ACCOUNT}" "${APPLICATION}" "${FOLDER}" "${SUBSCRIPTION_ID}" "${HTTP_CODE}"
    exit 1
fi
