#!/bin/bash
# ==============================================================================
# Script Name: 34.configurations_clusterManagement_nodeThreshold_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces the node threshold, using the
# `/configurations/clusterManagement/nodeThreshold` endpoint with PUT: the
# number of nodes expected, and an email when fewer are running.
#
# Usage:
# ./34.configurations_clusterManagement_nodeThreshold_PUT.sh [NODES]
#
#   NODES  the number of nodes expected (default 1)
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The email goes through the server's SMTP settings (the SMTP.Group options).
# - 35.configurations_clusterManagement_nodeThreshold_PATCH.sh turns the email
#   off again.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
NODES="${1:-1}"
[[ "${NODES}" =~ ^[1-9][0-9]*$ ]] || { printf "NODES must be a whole number: %s\n" "${NODES}"; exit 2; }
BODY=$(jq -cn --argjson nodes "${NODES}" '{numberOfNodes: $nodes, sendNotification: true,
  subject: "SecureTransport: fewer nodes than expected",
  notification: "Fewer than \($nodes) SecureTransport node(s) are running."}')

printf "Expecting %s node(s), with an email when fewer run...\n" "${NODES}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/clusterManagement/nodeThreshold" -H "accept: */*" \
  -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
