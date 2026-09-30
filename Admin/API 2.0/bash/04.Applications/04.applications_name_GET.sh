#!/bin/bash
# ==============================================================================
# Script Name: 04.applications_name_GET.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves information about a specific application using the
# `/applications/{name}` endpoint. It also checks whether business units are
# assigned to the application.
#
# Usage:
# ./04.applications_name_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Application names with spaces must be URL-encoded.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications"
NAME="AccountFilePurge%20Application"

curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "${MAIN_URL}/${NAME}" -H "accept: application/json" -H "${REFERER_HEADER}"

RESPONSE=$(curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "${MAIN_URL}/${NAME}" -H "accept: application/json" -H "${REFERER_HEADER}" | jq ."businessUnits")
NUMBER_OF_ASSIGNED_BU=$(echo "${RESPONSE}" | jq '. | length')

if [ "${NUMBER_OF_ASSIGNED_BU}" -eq 0 ]; then
    echo "No business units assigned to the application."
else
    echo "Business units assigned to the application: ${RESPONSE}"
fi
