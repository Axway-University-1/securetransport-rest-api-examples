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
# ./04.applications_name_GET.sh [NAME]
#
#   NAME  the application (default example_filepurge, one of the two 02.applications_POST.sh creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Application names with spaces must be URL-encoded: the script does it with jq.
# - On a server that already has an AccountFilePurge application, 02 does not create example_filepurge (only one is allowed): read example_humansystem instead.
# - Requires `jq`, which URL-encodes the name and reads the business units.
# - Confirmed directly: a flow application (HumanSystem) answers its type, id, name, notes, managedByCG, additionalAttributes and businessUnits and no `schedules`; a maintenance
#   application (read here only on an ArchiveMaint example) also answers `schedules`, with `startDate` as the epoch in milliseconds, written as text.
# - Exit codes: 0 when the server answered 200, 1 otherwise.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications"
NAME="${1:-example_filepurge}"
NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "${MAIN_URL}/${NAME_URI}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf '%s\n' "${RESPONSE}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    exit 1
fi

BUSINESS_UNITS=$(printf '%s' "${RESPONSE}" | jq -c '.businessUnits // []')
NUMBER_OF_ASSIGNED_BU=$(printf '%s' "${BUSINESS_UNITS}" | jq 'length')

if [ "${NUMBER_OF_ASSIGNED_BU}" -eq 0 ]; then
    echo "No business units assigned to the application."
else
    echo "Business units assigned to the application: ${BUSINESS_UNITS}"
fi
