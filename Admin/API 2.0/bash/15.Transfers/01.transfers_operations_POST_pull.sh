#!/bin/bash
# ==============================================================================
# Script Name: 01.transfers_operations_POST_pull.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script starts a pull from a partner, on demand, using the
# `/transfers/operations?operation=pull` endpoint. The files the site matches
# are downloaded into a folder of the account.
#
# Usage:
# ./01.transfers_operations_POST_pull.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The account "john" and its site SSH_PULL must already exist. Run
#   06.TransferSites/02.sites_POST_ssh.sh first.
# - With awaitResult false, SecureTransport answers 202 as soon as the pull is
#   accepted, and the pull runs on in the background. Follow it in File
#   Tracking, or with 16.TransferLogs/01.logs_transfers_GET.sh.
# - When the destination folder is subscribed to an application, as
#   07.Subscriptions/02.subscriptions_POST.sh sets up for /inbox, what arrives
#   there is routed.
# - Requires `jq`, which builds the request body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="john"
PULL_SITE="SSH_PULL"
DESTINATION_FOLDER="/inbox"

BODY=$(jq -n --arg account "${ACCOUNT}" --arg site "${PULL_SITE}" --arg folder "${DESTINATION_FOLDER}" \
  '{accountName: $account, site: $site, destinationDirectory: $folder, awaitResult: false}')

printf "Pulling with the site '%s' into '%s' of '%s'...\n" "${PULL_SITE}" "${DESTINATION_FOLDER}" "${ACCOUNT}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/transfers/operations?operation=pull" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -w "\nHTTP %{http_code}\n" -d "${BODY}"
