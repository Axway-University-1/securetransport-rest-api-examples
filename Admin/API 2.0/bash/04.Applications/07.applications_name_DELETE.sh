#!/bin/bash
# ==============================================================================
# Script Name: 07.applications_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes applications using the `/applications/{name}` endpoint.
# It demonstrates:
# - A direct DELETE request for a known application
# - A conditional DELETE request after verifying existence
#
# Usage:
# ./07.applications_name_DELETE.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Application names with spaces must be URL-encoded.
# - This cleans up the two applications 02.applications_POST.sh creates:
#   "AccountFilePurge Application" and "HumanSystem Application". Earlier
#   versions of this script named two different, pre-existing maintenance
#   applications here instead - on a real server those are the built-in
#   AuditLogMaint and TransferLogMaint housekeeping jobs, not test data, and
#   deleting them would have been a real mistake rather than cleanup. Only
#   ever point this at names this folder's own POST script created.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NAME="AccountFilePurge Application"
printf "Deleting application '%s'...\n" "${NAME}"
NAME=$(echo "${NAME}" | sed 's/ /%20/g')
curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "DELETE" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications/${NAME}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json"

NAME="HumanSystem Application"
NAME=$(echo "${NAME}" | sed 's/ /%20/g')
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications/${NAME}" \
-H "accept: */*" -H "${REFERER_HEADER}")
if [ "${RESPONSE_CODE}" == "200" ]; then
    printf "Application exists. Deleting application '%s'...\n" "${NAME}"
    curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "DELETE" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications/${NAME}" \
    -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json"
    printf "\nDone\n"
else
  echo "Application does not exist."
fi
