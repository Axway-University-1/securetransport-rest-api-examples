#!/bin/bash
# ==============================================================================
# Script Name: 35.configurations_clusterManagement_nodeThreshold_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script turns the node threshold email on or off, using the
# `/configurations/clusterManagement/nodeThreshold` endpoint with PATCH.
#
# Usage:
# ./35.configurations_clusterManagement_nodeThreshold_PATCH.sh [true|false]
#
#   whether to send the email (default false)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: a success answers 204, with no body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
SEND="${1:-false}"
[[ "${SEND}" =~ ^(true|false)$ ]] || { printf "The value is true or false, not %s.\n" "${SEND}"; exit 2; }

printf "sendNotification: %s...\n" "${SEND}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/clusterManagement/nodeThreshold" -H "accept: */*" \
  -H "${REFERER_HEADER}" -H "Content-Type: application/json" -w "\n%{http_code}" \
  -d "[{\"op\":\"replace\",\"path\":\"/sendNotification\",\"value\":${SEND}}]")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
