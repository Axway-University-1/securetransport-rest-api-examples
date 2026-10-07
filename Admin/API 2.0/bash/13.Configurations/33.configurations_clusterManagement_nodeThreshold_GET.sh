#!/bin/bash
# ==============================================================================
# Script Name: 33.configurations_clusterManagement_nodeThreshold_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the node threshold, using the
# `/configurations/clusterManagement/nodeThreshold` endpoint: how many nodes
# the server expects, and whether to send an email when fewer are running.
#
# Usage:
# ./33.configurations_clusterManagement_nodeThreshold_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/clusterManagement/nodeThreshold" -H "accept: application/json" \
  -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '"  expects \(.numberOfNodes) node(s); notification: \(.sendNotification)\(if .sendNotification then ", subject \(.subject)" else "" end)"'
