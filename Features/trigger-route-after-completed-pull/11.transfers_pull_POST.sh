#!/bin/bash
# ==============================================================================
# Script Name: 11.transfers_pull_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Runs the pull by hand, using the `/transfers/operations?operation=pull` endpoint,
# instead of waiting for a schedule. Files land in the subscription folder, and
# when the pull completes the trigger file starts one route execution.
#
# Usage:
# ./11.transfers_pull_POST.sh
#
# Notes:
# - Requires `jq`, which builds the JSON body.
# - Run steps 1 to 10 first.
# - A successful call answers 202: the pull is asynchronous. The response links
#   to /logs/transfers?operationIndex=... to follow it.
# - Afterwards look in the delivered folder, and in the transfer log: there should
#   be one route execution for all the pulled files.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

BODY=$(jq -n --arg account "${AR_TEST_ACCOUNT}" --arg site "${AR_PULL_SITE}" --arg folder "${AR_SUBSCRIPTION_FOLDER}" \
  '{accountName: $account, site: $site, destinationDirectory: $folder, awaitResult: false}')

printf "Pulling from %s into %s...\n" "${AR_PULL_SITE}" "${AR_SUBSCRIPTION_FOLDER}"
ar_admin_post "transfers/operations?operation=pull" "${BODY}"
