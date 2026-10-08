#!/bin/bash
# ==============================================================================
# Script Name: 01.applications_GET.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves application data using the `/applications` endpoint.
# It demonstrates:
# - A full GET request for all applications
# - A filtered GET request based on application type
# - A GET request for application types only
#
# Usage:
# ./01.applications_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The type filter uses a predefined list of application types.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# st_get CURL_ARGUMENTS...: a GET of the URL given (with any curl options, such as -G --data-urlencode ...). The answer
# is left in RESPONSE. A status other than 200 ends the script with exit 1, after printing the status and the answer.
st_get() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "$@" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}

printf "Get all applications...\n"
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications"
printf '%s' "${RESPONSE}"

ALL_TYPES="AccountFilePurge,AccountTTL,AdvancedRouting,ArchiveMaint,AuditLogMaint,Basic,HumanSystem,LogEntryMaint,LoginThresholdMaintenance,MBFT,PackageRetentionMaint,SentinelLinkDataMaint,SharedFolder,SiteMailbox,StandardRouter,TransferLogMaint,UnlicensedAccountMaint"
RANDOM_TYPE=$(echo $ALL_TYPES | awk -F ',' '{print $1}')
printf "From all applications get one based on the type '%s'...\n" "${RANDOM_TYPE}"
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications?type=${RANDOM_TYPE}"
printf '%s' "${RESPONSE}"

printf "Get only the type of the available applications...\n"
st_get "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications?fields=type"
printf '%s' "${RESPONSE}"
