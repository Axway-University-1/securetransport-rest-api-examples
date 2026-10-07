#!/bin/bash
# ==============================================================================
# Script Name: 02.configurations_PATCH_UsageReporting.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script configures automatic usage reporting to the Axway Platform by
# patching the StatisticsSummaryReport Server Configuration Options.
#
# Usage:
# ./02.configurations_PATCH_UsageReporting.sh
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Fill in the client, secret and environment values below before running.
# - Each option is patched with the matching value from the two arrays, so the
#   two lists must stay in the same order.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# 
# First we will load the variables into our context.
# Put your own values in set_variables.local.sh, which set_variables.sh
# loads and which git ignores.
#
printf "Loading variables into our context...\n\n"
source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

SCO="StatisticsSummaryReport"

#
# Those relate to the User and Environment you want to use from the Axway Platform
# You can find those in the Axway Platform UI
# https://platform.axway.com/
#
CLIENT_ID="<PUT YOUR CLIENT ID HERE>"
CLIENT_SECRET="<PUT YOUR CLIENT_SECRET HERE>"
ENVIRONMENT_ID="<PUT YOUR ENVIRONMENT_ID HERE>"
ENVIRONMENT_NAME="<PUT YOUR ENVIRONMENT_NAME HERE>"

#
# In case you have an edge through which the connection must pass to reach the platform, define it here.
#
NETWORK_ZONE="<PUT YOUR NETWORK_ZONE HERE>"

# Set the default values for the configuration options
# In newer product versions, those are set by default.
PLATFORM_API="https://platform.axway.com/api/v1/usage/automatic"
PLATFORM_AUTHENTICATION="https://login.axway.com/auth/realms/Broker/protocol/openid-connect/token"
SCHEMA_ID="https://platform.axway.com/schemas/report.json"

PATH_TO_REPORTS="/tmp/"
DAYS_TO_INCLUDE="3"

CONFIGURATION_OPTIONS=("${SCO}.ClientId" "${SCO}.ClientSecret" "${SCO}.EnvironmentId" "${SCO}.EnvironmentName" "${SCO}.FilePath" "${SCO}.NetworkZone" "${SCO}.Platform.API" "${SCO}.Platform.Authentication" "${SCO}.SchemaId" "${SCO}.AutomaticReport.DaysToInclude")
CONFIGURATION_VALUES=("${CLIENT_ID}" "${CLIENT_SECRET}" "${ENVIRONMENT_ID}" "${ENVIRONMENT_NAME}" "${PATH_TO_REPORTS}" "${NETWORK_ZONE}" "${PLATFORM_API}" "${PLATFORM_AUTHENTICATION}" "${SCHEMA_ID}" "${DAYS_TO_INCLUDE}")

# Update the configuration options
#
# Each iteration patches the option held in CONFIGURATION_OPTIONS[i] with the
# matching value from CONFIGURATION_VALUES[i]. The payload is enclosed in
# double quotes so that the value is expanded by the shell.
#
for i in "${!CONFIGURATION_OPTIONS[@]}"; do
  printf "Updating %s to '%s'...\n" "${CONFIGURATION_OPTIONS[$i]}" "${CONFIGURATION_VALUES[$i]}"
  curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH \
   "https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations/options/${CONFIGURATION_OPTIONS[$i]}" \
   -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
   -d "[{\"op\": \"replace\", \"path\": \"/values\", \"value\": [\"${CONFIGURATION_VALUES[$i]}\"]}]"
done