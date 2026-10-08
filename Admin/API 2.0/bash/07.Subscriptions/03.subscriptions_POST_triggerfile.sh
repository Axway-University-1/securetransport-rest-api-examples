#!/bin/bash
# ==============================================================================
# Script Name: 03.subscriptions_POST_triggerfile.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a subscription that writes a trigger file after each
# pull, and starts routing only when that trigger file arrives, using the
# `/subscriptions` endpoint. It demonstrates:
# - createFilesList, which writes the names of the pulled files into a trigger
#   file in the subscription folder
# - postTransmissionActions with submitFilterType TRIGGER_FILE_CONTENT, so the
#   route processes the files the trigger file lists, not each file on arrival
# - A trigger condition in Expression Language, so only a file whose name ends
#   in .trigger starts the route
#
# Usage:
# ./03.subscriptions_POST_triggerfile.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Run 02.subscriptions_POST.sh first. It creates the application and the
#   site this subscription uses.
# - The ${...} values below are Expression Language, filled in by
#   SecureTransport. They are not shell variables, so they are single quoted.
# - The condition holds a regular expression, and its dot is escaped with two
#   backslashes, \\., as SecureTransport needs. See
#   14.ExpressionLanguage/05.routes_step_condition_matches_backslashDoubling.sh.
# - Features/trigger-route-after-completed-pull runs this whole flow end to end.
# - 04.subscriptions_id_DELETE.sh removes the subscription again.
# - Requires `jq`, which builds the request body.
# - Exit codes: 0 when the subscription was created (201), 1 when the server refuses it. It takes no argument.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions"

if [ "$#" -ne 0 ]; then
    printf "Usage: ./03.subscriptions_POST_triggerfile.sh\n"
    exit 2
fi
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT

ACCOUNT="john"
APPLICATION="AdvancedRoutingApplication"
FOLDER="/inbox-trigger"
PULL_SITE="SSH_PULL"

# A new name for every pull, built from the date and time of the pull
TRIGGER_FILE_NAME='file_${date('"'"'yyyyddMMHHmmss'"'"')}.trigger'
# True for a file whose name ends in .trigger. The value holds two backslashes;
# jq writes each one escaped in the JSON text, and SecureTransport reads two back
TRIGGER_CONDITION='${stenv['"'"'target'"'"'].matches('"'"'.*\\.trigger'"'"')?1:0}'

BODY=$(jq -n --arg account "${ACCOUNT}" --arg application "${APPLICATION}" \
  --arg folder "${FOLDER}" --arg site "${PULL_SITE}" \
  --arg triggerName "${TRIGGER_FILE_NAME}" --arg condition "${TRIGGER_CONDITION}" \
  '{type: "AdvancedRouting", account: $account, application: $application, folder: $folder,
    transferConfigurations: [{tag: "PARTNER-IN", outbound: false, site: $site}],
    createFilesList: {createFilesListEnabled: true, createFilesListFilename: $triggerName},
    postTransmissionActions: {submitFilterType: "TRIGGER_FILE_CONTENT",
                              triggerFileOption: "fail",
                              triggerOnConditionEnabled: true,
                              triggerOnConditionExpression: $condition}}')

printf "Subscribing the folder '%s' of '%s' to '%s', with a trigger file...\n" "${FOLDER}" "${ACCOUNT}" "${APPLICATION}"
RESPONSE=$(curl -s -D "${HEADERS_FILE}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
LOCATION=$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r' | tail -n 1)
if [ -n "${LOCATION}" ]; then
    printf "New subscription ID: %s\n" "${LOCATION##*/}"
fi
