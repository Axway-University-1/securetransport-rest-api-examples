#!/bin/bash
# ==============================================================================
# Script Name: 02.applications_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script creates applications using the `/applications` endpoint.
# It demonstrates:
# - Checking for an existing application of a flow type
# - Creating a flow application if not found
# - Creating a maintenance application with a detailed schema
#
# Usage:
# ./02.applications_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Maintenance applications require specific schema fields.
# - Only one application of a given maintenance type is allowed per server -
#   confirmed against a real server, which rejected a second AccountFilePurge
#   application with "Only one instance of this type is allowed." This script
#   checks for one first, the same way it already does for the flow type
#   above, rather than assuming the POST will succeed.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

FLOW_APPLICATIONS=(AdvancedRouting Basic HumanSystem MBFT SharedFolder SiteMailbox StandardRouter)
MAINTENANCE_APPLICATIONS=(AccountFilePurge AccountTTL ArchiveMaint AuditLogMaint LogEntryMaint LoginThresholdMaintenance PackageRetentionMaint SentinelLinkDataMaint TransferLogMaint UnlicensedAccountMaint)

RANDOM_APP=${FLOW_APPLICATIONS[2]}
printf "Get the name of an application of type '%s'...\n" "${RANDOM_APP}"
NAME_OF_APP=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications?fields=name&type=${RANDOM_APP}" -H "accept: application/json" -H "${REFERER_HEADER}" | jq .result[0].name)
echo "Name of the application: ${NAME_OF_APP}"

if [ "${NAME_OF_APP}" == "null" ]; then
    echo "No application of type '${RANDOM_APP}' found."
    printf "Create an application of type '%s'...\n\n" "${RANDOM_APP}"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "POST" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications" -H 'accept: */*' -H "${REFERER_HEADER}" -H 'Content-Type: application/json' -d "{ \
    \"type\": \"${RANDOM_APP}\",
    \"name\": \"${RANDOM_APP} Application\",
    \"notes\": \"This is a ${RANDOM_APP} application\" }"
else
    printf "Application of type '%s' found.\n\n" "${RANDOM_APP}"
fi

RANDOM_APP=${MAINTENANCE_APPLICATIONS[0]}
printf "Get an application of type '%s'...\n" "${RANDOM_APP}"
NAME_OF_APP=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications?fields=name&type=${RANDOM_APP}" -H "accept: application/json" -H "${REFERER_HEADER}" | jq .result[0].name)
echo "Name of the application: ${NAME_OF_APP}"

if [ "${NAME_OF_APP}" == "null" ]; then
    echo "No application of type '${RANDOM_APP}' found."
    printf "Create an application of type '%s'...\n\n" "${RANDOM_APP}"
    # A ONCE schedule needs a start date in the future, so this is computed
    # relative to today rather than hardcoded to a date that will eventually
    # be in the past.
    START_DATE=$(date -u -v+1d +"%Y-%m-%dT00:00:00Z" 2>/dev/null || date -u -d "+1 day" +"%Y-%m-%dT00:00:00Z")
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "POST" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications" -H 'accept: */*' -H "${REFERER_HEADER}" -H 'Content-Type: application/json' -d "{ \
    \"type\": \"${RANDOM_APP}\",
    \"name\": \"${RANDOM_APP} Application\",
    \"notes\": \"This is a ${RANDOM_APP} application\",
    \"deleteFilesDays\": 90,
    \"pattern\": \"*.txt\",
    \"expirationPeriod\": true,
    \"removeFolders\": true,
    \"notifyDays\": \"90\",
    \"sendSentinelAlert\": false,
    \"warnNotifyAccount\": false,
    \"deletionNotifications\": false,
    \"deletionNotifyAccount\": false,
    \"schedules\": [ {
        \"tag\": \"${RANDOM_APP}\",
        \"type\": \"ONCE\",
        \"executionTimes\": [\"00:00\"],
        \"startDate\": \"${START_DATE}\",
        \"skipHolidays\": false
        }]
    }"
else
    printf "Application of type '%s' found.\n\n" "${RANDOM_APP}"
fi
