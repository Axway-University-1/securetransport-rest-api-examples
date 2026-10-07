#!/bin/bash
# ==============================================================================
# Script Name: 03.routes_POST_simple_compress.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a simple route that compresses the files it receives into
# one ZIP archive and sends the archive to a partner, using the `/routes`
# endpoint. It demonstrates:
# - A Compress step that builds a single archive
# - A SendToPartner step that sends only what the step before it produced
#   (usePrecedingStepFiles), so the archive goes out and the originals do not
# - Reading the id of the new route from the Location header
#
# Usage:
# ./03.routes_POST_simple_compress.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The site SSH_PUSH must already exist. Run
#   06.TransferSites/02.sites_POST_ssh.sh first.
# - A simple route does nothing on its own. A composite route runs it through an
#   ExecuteRoute step. See 05.routes_POST_composite_subscription.sh.
# - STORE puts the files in the archive without compressing them. Use another
#   compressionLevel to make the archive smaller.
# - Requires `jq`, which builds the request body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ROUTE_NAME="SimpleRoute_Compress"
PUSH_SITE="SSH_PUSH"
ARCHIVE_NAME="compressed_files.zip"

BODY=$(jq -n --arg name "${ROUTE_NAME}" --arg site "${PUSH_SITE}" --arg archive "${ARCHIVE_NAME}" \
  '{type: "SIMPLE", name: $name, conditionType: "ALWAYS", condition: true,
    steps: [
      {type: "Compress", status: "ENABLED", conditionType: "ALWAYS",
       usePrecedingStepFiles: false, fileFilterExpressionType: "GLOB", fileFilterExpression: "*",
       singleArchiveEnabled: true, singleArchiveName: $archive,
       compressionType: "ZIP", compressionLevel: "STORE",
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
