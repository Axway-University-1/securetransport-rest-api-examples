#!/bin/bash
# ==============================================================================
# Script Name: 07.subscriptions_id_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a subscription, using the `/subscriptions/{id}` endpoint with
# PUT: it reads the subscription, changes how many pulls it may run at once
# (maxParallelSitPulls), and sends the whole subscription back.
#
# Usage:
# ./07.subscriptions_id_PUT.sh ACCOUNT APPLICATION FOLDER [VALUE]
#
#   ACCOUNT      the account that subscribes
#   APPLICATION  the application it subscribes to
#   FOLDER       the folder of the subscription
#   VALUE        the new maxParallelSitPulls, a whole number, 0 or more (default 2; 0 is no limit)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The subscription is looked up by account, application and folder, and must be the only one
#   that matches. A subscription is addressed by a generated id, and an account may have several
#   on one application as long as their folders differ.
# - It prints the value before, to put it back with.
# - PUT replaces the whole subscription. Confirmed directly: a body with only the type, account,
#   application and folder answers 204 and silently drops the transfer configurations (the pull
#   sites), the flow attributes and every setting it leaves out. That is why the subscription is
#   read first and sent back with one field changed. `metadata`, the read-only links, is left out.
# - Confirmed directly: a success answers 204, with no body, and the same subscription sent back
#   unchanged changes nothing. An id that is not one is 400 "Subscription for ID: X not found", not
#   the 404 the reference lists (GET, PATCH and DELETE answer 404). A body with no `type` is 400
#   "Invalid discriminator value."; another type is 400 with a misleading "Unsupported parameter -
#   postClientDownloads". An `account` that does not exist is 404 (with a transfer configuration in
#   the body, a bare 403 "unable to comply"); an `application` other than the
#   subscription's is accepted (204) and ignored; another `folder` moves the subscription. A negative
#   maxParallelSitPulls is 400, a word is 400 "Cannot parse 'abc' to Integer.".
# - A transfer configuration sent without its `id` is stored with a new one, and one sent with an id
#   that no longer exists is 400 "you are trying to update transfer configuration with id X that
#   does not exists": read the subscription again before sending it back. fileRetentionPeriod
#   (0 to 36500) needs a transfer site: 400 "Cannot set file retention period without setting
#   transfer site." without one. A flow attribute key must start with `userVars.`, hold only
#   letters, digits, `.` and `_`, and not repeat `userVars.`; its value is 1 to 4000 characters.
# - Requires `jq`, which reads the id and edits the subscription.
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
[ -n "${ACCOUNT}" ] && [ -n "${APPLICATION}" ] && [ -n "${FOLDER}" ] || { printf "Usage: ./07.subscriptions_id_PUT.sh ACCOUNT APPLICATION FOLDER [VALUE]\n"; exit 2; }
VALUE="${4:-2}"
[[ "${VALUE}" =~ ^[0-9]{1,9}$ ]] || { printf "VALUE is a whole number, 0 or more, not %s.\n" "${VALUE}"; exit 2; }

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
printf "maxParallelSitPulls of the subscription is now %s.\n" "$(printf '%s' "${SUBSCRIPTION_JSON}" | jq -r '.maxParallelSitPulls // "(not set)"')"
BODY=$(printf '%s' "${SUBSCRIPTION_JSON}" | jq -c --argjson value "${VALUE}" '.maxParallelSitPulls = $value | del(.metadata)')

printf "Setting it to %s...\n" "${VALUE}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${SUBSCRIPTION_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
