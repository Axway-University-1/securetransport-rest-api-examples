#!/bin/bash
# ==============================================================================
# Script Name: 12.subscriptions_POST_types.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script subscribes an account to one application of each of four other types, using
# the `/applications` and `/subscriptions` endpoints. 02.subscriptions_POST.sh
# shows Advanced Routing; the others are:
# - Basic
# - HumanSystem (Human to System)
# - MBFT (File Transfer via File Services)
# - StandardRouter, which also needs the subscriber's ID
#
# Usage:
# ./12.subscriptions_POST_types.sh [ACCOUNT]
#
#   ACCOUNT  the account to subscribe (default john)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It creates the applications ExampleBasicApplication, ExampleHumanSystemApplication,
#   ExampleMBFTApplication and ExampleStandardRouterApplication, and the subscriptions on the folders
#   /example_Basic, /example_HumanSystem, /example_MBFT and /example_StandardRouter of the account.
#   13.subscriptions_id_DELETE_types.sh removes them again.
# - An application that exists already is refused (400 "An application with this name already exists.",
#   not a 409) and the subscription is created against it.
# - Confirmed directly on the lab: Basic, HumanSystem, MBFT and StandardRouter subscribe with
#   only the type, account, application and folder (StandardRouter also needs `subscriberID`, 400
#   "A valid subscriberID should be specified..." without it). SharedFolder and SiteMailbox need more
#   from their application first (a `sharedFolder`; an `inboxFolder` and `outboxFolder`), and a
#   SiteMailbox subscription needs an inbound transfer configuration, 400 "SiteMailbox application type
#   requires inbound transfer configuration."; they are not shown here.
# - The folders are not made by the POST: they appear in the account's home folder at its next login.
# - The type of the subscription is the type of its application: a body that says another type is
#   accepted and the application's type wins. The folder needs no leading /. A second subscription
#   on the same application and folder (and, for StandardRouter, the same subscriberID) is 400
#   "All subscriptions to an application should have a unique anchor.". An application that has
#   subscriptions cannot be deleted, 400 "has active subscriptions"; deleting the account deletes its
#   subscriptions.
# - A HumanSystem subscription takes `rules` (enabled, recipientPattern, fileFilterPattern,
#   targetFolder); this script sets one.
# - Requires `jq`, which builds the request bodies.
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

    BODY=$(jq -n --arg type "${TYPE}" --arg name "${APPLICATION}" \
      '{type: $type, name: $name, notes: "Created by 07.Subscriptions"}')
    printf "Creating the %s application '%s'...\n" "${TYPE}" "${APPLICATION}"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications" \
      -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
      -w "HTTP %{http_code}\n" -d "${BODY}"

    # StandardRouter names the subscriber; HumanSystem may route files by rules
    BODY=$(jq -n --arg type "${TYPE}" --arg account "${ACCOUNT}" --arg application "${APPLICATION}" --arg folder "${FOLDER}" \
      '{type: $type, account: $account, application: $application, folder: $folder}
       + (if $type == "StandardRouter" then {subscriberID: "EXAMPLE_SUBSCRIBER"} else {} end)
       + (if $type == "HumanSystem" then {rules: [{enabled: true, recipientPattern: "*", fileFilterPattern: "*.txt", targetFolder: "/example_targets"}]} else {} end)')
    printf "Subscribing the folder '%s' of '%s' to '%s'...\n" "${FOLDER}" "${ACCOUNT}" "${APPLICATION}"
    response_headers=$(mktemp)
    curl -s -D "${response_headers}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
      -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}"
    HTTP_CODE=$(head -n 1 "${response_headers}" | awk '{print $2}')
    LOCATION=$(grep -i '^Location:' "${response_headers}" | awk '{print $2}' | tr -d '\r')
    rm -f "${response_headers}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" = "201" ]; then
        printf "New subscription ID: %s\n" "$(basename "${LOCATION}")"
    else
        FAILED=1
    fi
done
[ "${FAILED}" = "0" ]
