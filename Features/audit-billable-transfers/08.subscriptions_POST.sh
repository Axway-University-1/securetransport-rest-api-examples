#!/bin/bash
# ==============================================================================
# Script Name: 08.subscriptions_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the six Advanced Routing subscriptions these examples use, using the
# `/subscriptions` endpoint, one per scenario, each pulling from its own site
# (see 02.sites_POST_pull.sh) into its own folder (subscription/s1 to s6).
#
# Scenario 2.1 (only inbound) and scenarios 2.2, 2.3, 2.5 and 2.6 use no special
# trigger settings: by default, a subscription attached to a route (via that
# route's own `subscriptions` field, see 10.routes_POST_composite.sh) runs the
# route once per file as it arrives. Scenario 2.1 has no route attached at all,
# so its files just land.
#
# Scenario 2.4 is the one exception: its two files (file_1_for_compress.txt and
# file_2_for_compress.txt) need to be compressed together, in ONE route
# execution, so it uses the same batching mechanism as
# Features/trigger-route-after-completed-pull: a generated trigger file listing
# every file the pull just fetched, submitted as the one thing the route acts on.
#
# Usage:
# ./08.subscriptions_POST.sh
#
# Risk: write
#
# Notes:
# - Run 02.sites_POST_pull.sh and 05.applications_POST.sh first.
# - Requires `jq`, which builds the JSON bodies.
# - The ids are saved as BT_ID_SUBSCRIPTION_1 to BT_ID_SUBSCRIPTION_6.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

create_subscription() {
    local n="$1" extra="$2"
    local name_site="${BT_PULL_SITE_PREFIX}${n}"
    local folder="${BT_SUBSCRIPTION_FOLDER}/s${n}"
    local body
    body=$(jq -n \
      --arg account "${BT_TEST_ACCOUNT}" \
      --arg application "${BT_APPLICATION}" \
      --arg folder "${folder}" \
      --arg site "${name_site}" \
      --argjson extra "${extra}" \
      '{type: "AdvancedRouting", application: $application, account: $account, folder: $folder,
        transferConfigurations: [{tag: "PARTNER-IN", outbound: false, site: $site}]} * $extra')

    printf "Creating the subscription for scenario %s, on %s...\n" "${n}" "${folder}"
    ar_admin_post "subscriptions" "${body}" "BT_ID_SUBSCRIPTION_${n}"
}

# Scenario 2.4's batching: a trigger file listing both pulled files, submitted
# whole once it arrives (see Features/trigger-route-after-completed-pull for
# how this was confirmed against a real server)
TRIGGER_EXTRA=$(jq -n --arg name "file_\${date('yyyyddMMHHmmss')}.trigger" \
  --arg condition "\${stenv['target'].matches('.*\\\\.trigger')?1:0}" \
  '{createFilesList: {createFilesListEnabled: true, createFilesListFilename: $name},
    postTransmissionActions: {submitFilterType: "TRIGGER_FILE_CONTENT",
                               triggerFileOption: "fail",
                               triggerOnConditionEnabled: true,
                               triggerOnConditionExpression: $condition}}')

create_subscription 1 '{}'
create_subscription 2 '{}'
create_subscription 3 '{}'
create_subscription 4 "${TRIGGER_EXTRA}"
create_subscription 5 '{}'
create_subscription 6 '{}'
