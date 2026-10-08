#!/bin/bash
# ==============================================================================
# Script Name: 08.subscriptions_id_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script changes one property of a subscription, using the
# `/subscriptions/{id}` endpoint with PATCH: a JSON Patch document that adds one
# flow attribute (a userVars key that the routes of the subscription can read).
# Unlike PUT (07.subscriptions_id_PUT.sh), it sends only what changes.
#
# Usage:
# ./08.subscriptions_id_PATCH.sh ACCOUNT APPLICATION FOLDER [VALUE]
#
#   ACCOUNT      the account that subscribes
#   APPLICATION  the application it subscribes to
#   FOLDER       the folder of the subscription
#   VALUE        the value of the flow attribute userVars.example_note (default example)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The subscription is looked up by account, application and folder, and must be the only one
#   that matches. A subscription is addressed by a generated id, and an account may have several
#   on one application as long as their folders differ.
# - It prints the value before, to put it back with.
# - Confirmed directly: a success answers 204, with no body. `add` sets a flow attribute whether
#   or not it exists (an existing value is overwritten); `replace` of one that does not exist is
#   400 `Missing field "userVars.x"`, of one that does is 204; `remove` deletes it. `replace` of a
#   field that is null (maxParallelSitPulls) works, and `remove` of it sets it back to null. The
#   value cannot be empty or blank (400 "Attribute value cannot be empty.") or over 4000
#   characters. `type` is read only (400 "Patch operation on read only or discriminator fields is
#   not permitted."); `replace` of `/id` and of `/application` answer 204 and change nothing; of
#   `/account` to one that does not exist 404; of `/folder` it moves the subscription. A path
#   that does not exist is 400 `Missing field "nosuch"`, an empty patch is 204, `add` to
#   `/transferConfigurations/-` adds a transfer configuration, an unknown id is a JSON 404.
# - Requires `jq`, which reads the id and builds the patch.
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
[ -n "${ACCOUNT}" ] && [ -n "${APPLICATION}" ] && [ -n "${FOLDER}" ] || { printf "Usage: ./08.subscriptions_id_PATCH.sh ACCOUNT APPLICATION FOLDER [VALUE]\n"; exit 2; }
VALUE="${4:-example}"
[ -n "${VALUE//[[:space:]]/}" ] || { printf "VALUE cannot be empty.\n"; exit 2; }
KEY="userVars.example_note"

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

SUBSCRIPTION_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${SUBSCRIPTION_ID}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${SUBSCRIPTION_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the subscription %s.\n" "${SUBSCRIPTION_ID}"
    exit 1
fi
printf "The flow attribute %s is now %s.\n" "${KEY}" "$(printf '%s' "${SUBSCRIPTION_JSON}" | jq -r --arg key "${KEY}" '.flowAttributes[$key] // "(not set)"')"
BODY=$(jq -n --arg key "${KEY}" --arg value "${VALUE}" '[{op: "add", path: "/flowAttributes/\($key)", value: $value}]')

printf "Setting it to %s...\n" "${VALUE}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${SUBSCRIPTION_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
