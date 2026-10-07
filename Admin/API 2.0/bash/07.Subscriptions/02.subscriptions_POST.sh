#!/bin/bash
# ==============================================================================
# Script Name: 02.subscriptions_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script subscribes an account's folder to an Advanced Routing application,
# using the `/applications` and `/subscriptions` endpoints. It demonstrates:
# - Creating the Advanced Routing application the subscription needs
# - Creating the subscription, with the pull site as its PARTNER-IN transfer
#   configuration, so that what the site pulls lands in the folder
# - Reading the id of the new subscription from the Location header
#
# Usage:
# ./02.subscriptions_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The account "john" and its site SSH_PULL must already exist. Run
#   06.TransferSites/02.sites_POST_ssh.sh first.
# - If the application already exists, its POST answers 409 and the
#   subscription is created against the existing one.
# - A route only runs on what arrives in the folder once a composite route is
#   linked to the subscription. See
#   09.CompositeRoutes/05.routes_POST_composite_subscription.sh.
# - Requires `jq`, which builds the request bodies.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="john"
APPLICATION="AdvancedRoutingApplication"
FOLDER="/inbox"
PULL_SITE="SSH_PULL"

BODY=$(jq -n --arg name "${APPLICATION}" \
  '{type: "AdvancedRouting", name: $name, notes: "Created by 07.Subscriptions"}')

printf "Creating the application '%s'...\n" "${APPLICATION}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -w "\nHTTP %{http_code}\n" -d "${BODY}"

BODY=$(jq -n --arg account "${ACCOUNT}" --arg application "${APPLICATION}" \
  --arg folder "${FOLDER}" --arg site "${PULL_SITE}" \
  '{type: "AdvancedRouting", account: $account, application: $application, folder: $folder,
    transferConfigurations: [{tag: "PARTNER-IN", outbound: false, site: $site}]}')

printf "Subscribing the folder '%s' of '%s' to '%s'...\n" "${FOLDER}" "${ACCOUNT}" "${APPLICATION}"

# Create a temporary file to store the response headers
response_headers=$(mktemp)

curl -s -D "${response_headers}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}"

HTTP_CODE=$(head -n 1 "${response_headers}" | awk '{print $2}')
LOCATION=$(grep -i '^Location:' "${response_headers}" | awk '{print $2}' | tr -d '\r')
rm -f "${response_headers}"

printf "\nHTTP %s\n" "${HTTP_CODE}"
if [ -n "${LOCATION}" ]; then
    printf "New subscription ID: %s\n" "$(basename "${LOCATION}")"
fi
