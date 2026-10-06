#!/bin/bash
# ==============================================================================
# Script Name: 04.subscriptions_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes subscriptions using the `/subscriptions/{id}` endpoint,
# and then the application they used. It demonstrates:
# - Looking up the id of a subscription by account and folder
# - Deleting the subscription by that id
# - Deleting the application, once nothing subscribes to it
#
# Usage:
# ./04.subscriptions_id_DELETE.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This cleans up what 02.subscriptions_POST.sh and
#   03.subscriptions_POST_triggerfile.sh create for the account "john": the
#   subscriptions on /inbox and /inbox-trigger, and the application
#   AdvancedRoutingApplication. Only ever point it at what you created.
# - Delete a composite route that is linked to a subscription first. See
#   09.CompositeRoutes/07.routes_id_DELETE.sh.
# - Requires `jq`, which picks the subscription out of the response.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="john"
APPLICATION="AdvancedRoutingApplication"

for FOLDER in "/inbox" "/inbox-trigger"; do
    SUBSCRIPTION_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions?account=${ACCOUNT}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" \
      | jq -r --arg folder "${FOLDER}" --arg application "${APPLICATION}" \
        '[(.result // [])[] | select(.folder == $folder and .application == $application)][0].id // empty')

    if [ -z "${SUBSCRIPTION_ID}" ]; then
        printf "The account '%s' has no subscription on '%s'.\n" "${ACCOUNT}" "${FOLDER}"
        continue
    fi

    printf "Deleting the subscription on '%s' (%s)...\n" "${FOLDER}" "${SUBSCRIPTION_ID}"
    curl -s -o /dev/null -w "HTTP %{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions/${SUBSCRIPTION_ID}" \
      -H "accept: */*" -H "${REFERER_HEADER}"
done

printf "Deleting the application '%s'...\n" "${APPLICATION}"
curl -s -o /dev/null -w "HTTP %{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE \
  "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications/${APPLICATION}" \
  -H "accept: */*" -H "${REFERER_HEADER}"
