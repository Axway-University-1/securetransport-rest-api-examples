#!/bin/bash
# ==============================================================================
# Script Name: 03.applications_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks if specific applications exist using the `/applications/{name}` endpoint.
# It demonstrates:
# - A HEAD request to verify existence of an application by name
# - Conditional logic based on HTTP response code
#
# Usage:
# ./03.applications_name_HEAD.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Application names with spaces must be URL-encoded.
# - Checks the two applications 02.applications_POST.sh creates. Run that
#   script first, or both checks will report "does not exist".
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NAME="AccountFilePurge Application"
NAME=$(echo "${NAME}" | sed 's/ /%20/g')
printf "Check if application with the name '%s' exists...\n" "${NAME}"
curl -k -u "${ST_USER}:${ST_PASSWORD}" --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications/${NAME}" -H "accept: */*" -H "${REFERER_HEADER}"

NAME="HumanSystem Application"
NAME=$(echo "${NAME}" | sed 's/ /%20/g')
printf "\nCheck if application with the name '%s' exists...\n" "${NAME}"
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications/${NAME}" -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${RESPONSE_CODE}" == "200" ]; then
  echo "Application exists."
else
  echo "Application does not exist."
fi
