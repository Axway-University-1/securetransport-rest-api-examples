#!/bin/bash
# ==============================================================================
# Script Name: 13.subscriptions_id_DELETE_types.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes the subscriptions that 12.subscriptions_POST_types.sh creates, and
# the applications they used, using the `/subscriptions/{id}` endpoint. It
# demonstrates:
# - Looking up the id of a subscription by account, application and folder
# - Deleting it with purge=true, which also removes the subscription's folder
# - Deleting the application, once nothing subscribes to it
#
# Usage:
# ./13.subscriptions_id_DELETE_types.sh [ACCOUNT]
#
#   ACCOUNT  the account that was subscribed (default john)
#
# Risk: write - deletes the subscriptions of 12 and, with purge=true, their folders
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It only touches the applications ExampleBasicApplication, ExampleHumanSystemApplication,
#   ExampleMBFTApplication and ExampleStandardRouterApplication and the subscriptions of the account
#   on them, on the folders /example_Basic, /example_HumanSystem, /example_MBFT and
#   /example_StandardRouter. Files in those folders are deleted with them.
# - Confirmed directly: `?purge=true` removes the folder of the subscription from the account's home
#   folder; without it the folder stays. The answer is 204 either way. The applications are deleted
#   after their subscription: an application with a subscription is 400 "has active subscriptions".
# - Requires `jq`, which picks the subscription out of the response.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions"
ACCOUNT="${1:-john}"
FAILED=0

for TYPE in Basic HumanSystem MBFT StandardRouter; do
    APPLICATION="Example${TYPE}Application"
    FOLDER="/example_${TYPE}"

    # The one subscription of that account on that application and folder: "1 <id>",
    # or how many there are. The account and application filters are exact; the
    # application and the folder are compared again here, on what comes back.
    read -r FOUND SUBSCRIPTION_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
      --data-urlencode "account=${ACCOUNT}" --data-urlencode "application=${APPLICATION}" --data-urlencode "fields=id,application,folder" \
      -H "accept: application/json" -H "${REFERER_HEADER}" \
      | jq -r --arg application "${APPLICATION}" --arg folder "${FOLDER}" \
        '[(.result // [])[] | select(.application == $application and .folder == $folder)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
    if [ "${FOUND}" = "1" ]; then
        printf "Deleting the subscription on '%s' (%s), and its folder...\n" "${FOLDER}" "${SUBSCRIPTION_ID}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${SUBSCRIPTION_ID}?purge=true" \
          -H "accept: */*" -H "${REFERER_HEADER}")
        printf "HTTP %s\n" "${HTTP_CODE}"
        [ "${HTTP_CODE}" = "204" ] || FAILED=1
    else
        printf "Found %s subscriptions of the account %s on the application %s and the folder %s; none deleted.\n" "${FOUND:-0}" "${ACCOUNT}" "${APPLICATION}" "${FOLDER}"
        [ "${FOUND:-0}" = "0" ] || FAILED=1
    fi

    printf "Deleting the application '%s'...\n" "${APPLICATION}"
    curl -s -o /dev/null -w "HTTP %{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications/${APPLICATION}" \
      -H "accept: */*" -H "${REFERER_HEADER}"
done
[ "${FAILED}" = "0" ]
