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
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The type filter uses a predefined list of application types.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

printf "Get all applications...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications" -H "accept: application/json" -H "${REFERER_HEADER}"

ALL_TYPES="AccountFilePurge,AccountTTL,AdvancedRouting,ArchiveMaint,AuditLogMaint,Basic,HumanSystem,LogEntryMaint,LoginThresholdMaintenance,MBFT,PackageRetentionMaint,SentinelLinkDataMaint,SharedFolder,SiteMailbox,StandardRouter,TransferLogMaint,UnlicensedAccountMaint"
RANDOM_TYPE=$(echo $ALL_TYPES | awk -F ',' '{print $1}')
printf "From all applications get one based on the type '${RANDOM_TYPE}'...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications?type=${RANDOM_TYPE}" -H "accept: application/json" -H "${REFERER_HEADER}"

printf "Get only the type of the available applications...\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications?fields=type" -H "accept: application/json" -H "${REFERER_HEADER}"
