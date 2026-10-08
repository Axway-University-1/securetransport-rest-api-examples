#!/bin/bash
# ==============================================================================
# Script Name: 03.applications_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks if an application exists using the `/applications/{name}` endpoint.
# It demonstrates:
# - A HEAD request to verify existence of an application by name, with the name URL-encoded
# - Conditional logic based on the HTTP response code
#
# Usage:
# ./03.applications_name_HEAD.sh [NAME]
#
#   NAME  the application (default example_filepurge, one of the two 02.applications_POST.sh creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Application names with spaces must be URL-encoded: the script does it with jq (a space is %20).
# - Run 02.applications_POST.sh first, or the answer is "does not exist". On a server that already has an AccountFilePurge application, 02 does not create example_filepurge
#   (only one is allowed): check example_humansystem instead.
# - Requires `jq`, which URL-encodes the name.
# - Confirmed directly: 200 when the application exists and 404 when it does not, with no body; a name with a space is found by its %20 form.
# - Exit codes: 0 when the application exists, 1 when it does not (404) or the server answers otherwise.
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
printf "Check if application with the name '%s' exists...\n" "${NAME}"
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${NAME_URI}" -H "accept: */*" -H "${REFERER_HEADER}")
printf "HTTP %s\n" "${RESPONSE_CODE}"
if [ "${RESPONSE_CODE}" == "200" ]; then
  echo "Application exists."
elif [ "${RESPONSE_CODE}" == "404" ]; then
  echo "Application does not exist."
  exit 1
else
  echo "Could not tell whether the application exists."
  exit 1
fi
