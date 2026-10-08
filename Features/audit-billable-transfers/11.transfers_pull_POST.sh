#!/bin/bash
# ==============================================================================
# Script Name: 11.transfers_pull_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Runs all six pulls by hand, using the `/transfers/operations?operation=pull`
# endpoint, instead of waiting for a schedule. Each pull uses its own site, so it
# only ever fetches the file(s) for its own scenario, landing in that
# scenario's own subscription folder.
#
# Usage:
# ./11.transfers_pull_POST.sh
#
# Risk: write
#
# Notes:
# - Run steps 01 to 10 first.
# - Requires `jq`, which builds the JSON bodies.
# - Stops at the first pull the server refuses, and exits 1.
# - Each call answers 202 on success: the pull is asynchronous. 00.run_all.sh
#   pauses afterwards to give the pulls, and the routes they trigger, time to run.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

run_pull() {
    local n="$1"
    local site="${BT_PULL_SITE_PREFIX}${n}"
    local folder="${BT_SUBSCRIPTION_FOLDER}/s${n}"
    local body
    body=$(jq -n --arg account "${BT_TEST_ACCOUNT}" --arg site "${site}" --arg folder "${folder}" \
      '{accountName: $account, site: $site, destinationDirectory: $folder, awaitResult: false}')

    printf "Pulling from %s into %s...\n" "${site}" "${folder}"
    ar_admin_post "transfers/operations?operation=pull" "${body}"
}

for n in 1 2 3 4 5 6; do
    run_pull "${n}" || exit 1
done
