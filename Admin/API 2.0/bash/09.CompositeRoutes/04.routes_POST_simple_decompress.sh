#!/bin/bash
# ==============================================================================
# Script Name: 04.routes_POST_simple_decompress.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a simple route that unpacks the archives it receives and
# sends the files inside them to a partner, using the `/routes` endpoint.
# It demonstrates:
# - A Decompress step, which overwrites a file of the same name
# - A SendToPartner step that sends only what the step before it produced
#   (usePrecedingStepFiles), so the unpacked files go out and the archive does not
# - Reading the id of the new route from the Location header
#
# Usage:
# ./04.routes_POST_simple_decompress.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The site SSH_PUSH must already exist. Run
#   06.TransferSites/02.sites_POST_ssh.sh first.
# - A simple route does nothing on its own. A composite route runs it through an
#   ExecuteRoute step. See 05.routes_POST_composite_subscription.sh.
# - Requires `jq`, which builds the request body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ROUTE_NAME="SimpleRoute_Decompress"
PUSH_SITE="SSH_PUSH"

BODY=$(jq -n --arg name "${ROUTE_NAME}" --arg site "${PUSH_SITE}" \
  '{type: "SIMPLE", name: $name, conditionType: "ALWAYS", condition: true,
    steps: [
      {type: "Decompress", status: "ENABLED", conditionType: "ALWAYS",
       usePrecedingStepFiles: false, fileFilterExpressionType: "GLOB", fileFilterExpression: "*",
       filenameCollisionResolutionType: "OVERWRITE",
       actionOnStepFailure: "FAIL"},
      {type: "SendToPartner", status: "ENABLED", conditionType: "ALWAYS", autostart: false,
       usePrecedingStepFiles: true, fileFilterExpressionType: "GLOB", fileFilterExpression: "*",
       transferSiteExpressionType: "LIST", transferSiteExpression: ($site + "#!#CVD#!#"),
       actionOnStepFailure: "FAIL"}]}')

printf "Creating the simple route '%s'...\n" "${ROUTE_NAME}"

# Create a temporary file to store the response headers
response_headers=$(mktemp)

curl -s -D "${response_headers}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}"

HTTP_CODE=$(head -n 1 "${response_headers}" | awk '{print $2}')
LOCATION=$(grep -i '^Location:' "${response_headers}" | awk '{print $2}' | tr -d '\r')
rm -f "${response_headers}"

printf "\nHTTP %s\n" "${HTTP_CODE}"
if [ -n "${LOCATION}" ]; then
    printf "New route ID: %s\n" "$(basename "${LOCATION}")"
fi
