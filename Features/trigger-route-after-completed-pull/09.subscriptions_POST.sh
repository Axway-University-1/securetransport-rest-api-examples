#!/bin/bash
# ==============================================================================
# Script Name: 09.subscriptions_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the Advanced Routing subscription that is the point of this feature,
# using the `/subscriptions` endpoint. It pulls from the pull site, writes a
# trigger file that lists every pulled file, and runs the route once, after the
# whole pull, on the files named in that trigger file.
#
# Usage:
# ./09.subscriptions_POST.sh
#
# Risk: write
#
# Notes:
# - Requires `jq`, which builds the JSON body.
# - Run 02.sites_POST_pull.sh and 08.applications_POST.sh first: the subscription
#   names the pull site and the application.
# - The trigger file name and the trigger condition come from settings.sh, so the
#   condition always matches the name. The ${date(...)} in the name is evaluated
#   by SecureTransport, once per pull.
# - triggerOnConditionEnabled switches on 'Trigger route execution based on
#   condition'. The server refuses the condition without it.
# - submitFilterType TRIGGER_FILE_CONTENT is 'Files read from trigger file
#   content'. triggerFileOption fail means the run fails if a listed file is
#   missing. Do not use retry here: it does not re-run the pull.
# - The id is saved as AR_ID_SUBSCRIPTION for the later steps.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

BODY=$(jq -n \
  --arg account "${AR_TEST_ACCOUNT}" \
  --arg application "${AR_APPLICATION}" \
  --arg folder "${AR_SUBSCRIPTION_FOLDER}" \
  --arg site "${AR_PULL_SITE}" \
  --arg triggerName "${AR_TRIGGER_FILE_NAME}" \
  --arg condition "${AR_TRIGGER_CONDITION}" \
  '{type: "AdvancedRouting", application: $application, account: $account, folder: $folder,
    transferConfigurations: [{tag: "PARTNER-IN", outbound: false, site: $site}],
    createFilesList: {createFilesListEnabled: true, createFilesListFilename: $triggerName},
    postTransmissionActions: {submitFilterType: "TRIGGER_FILE_CONTENT",
                              triggerFileOption: "fail",
                              triggerOnConditionEnabled: true,
                              triggerOnConditionExpression: $condition}}')

printf "Creating the subscription on %s...\n" "${AR_SUBSCRIPTION_FOLDER}"
ar_admin_post "subscriptions" "${BODY}" AR_ID_SUBSCRIPTION
