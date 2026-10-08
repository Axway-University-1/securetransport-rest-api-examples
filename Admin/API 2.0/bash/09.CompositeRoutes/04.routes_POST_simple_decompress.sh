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
# - The HTTP code, from curl itself (-w), not from the head of a headers file
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
# - 07.routes_id_DELETE.sh removes the route again.
# - Requires `jq`, which builds the request body.
# - Confirmed directly: a creation is 201 with no body and the route's address in `Location`, which ends with its id. Run again it makes a second
#   route of the same name (201 again): two simple routes may share a name. 07.routes_id_DELETE.sh then refuses that name until one is removed by its id.
# - Exit codes: 0 when the route was created (201), 1 when the server refuses it. It takes no argument.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"

if [ "$#" -ne 0 ]; then
    printf "Usage: ./%s\n" "$(basename "$0")"
    exit 2
fi
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT

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
RESPONSE=$(curl -s -D "${HEADERS_FILE}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
LOCATION=$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r' | tail -n 1)
if [ -n "${LOCATION}" ]; then
    printf "New route ID: %s\n" "${LOCATION##*/}"
fi
