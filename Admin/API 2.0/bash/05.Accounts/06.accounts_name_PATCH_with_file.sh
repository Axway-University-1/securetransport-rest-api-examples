#!/bin/bash
# ==============================================================================
# Script Name: 06.accounts_name_PATCH_with_file.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script performs a partial update to an account using the
# `/accounts/{name}` endpoint, reading the PATCH body from a file instead of
# building it on the command line.
# It demonstrates:
# - Keeping the request body in a separate, reusable JSON file
# - Reading a value out of that file to report what is being changed
# - Checking the HTTP response code instead of printing the whole response
#
# Usage:
# ./06.accounts_name_PATCH_with_file.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The 06.patch_body folder holds one file per example change. Point
#   PATCH_FILE at whichever one you want to apply.
# - Requires `jq`, which reads the path out of the patch body.
# - A successful PATCH returns 204 with no response body.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# 
# First we will load the variables into our context.
# Put your own values in set_variables.local.sh, which set_variables.sh
# loads and which git ignores.
#
printf "Loading variables into our context...\n"
source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="john"
PATCH_FILE="${SCRIPT_DIR}/06.patch_body/stPatchAccount.json"


ELEMENT_TO_BE_CHANGED=$(jq -r '.[] | .path' "${PATCH_FILE}")

printf "Changing '%s' of account '%s'...\n" "${ELEMENT_TO_BE_CHANGED}" "${ACCOUNT}"
HTTP_CODE=$(curl -s -o /dev/null -k -u ${ST_USER}:${ST_PASSWORD} -w "%{http_code}\n" -X PATCH "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}" -H "accept: */*" -H "${REFERER_HEADER}" -H 'Content-Type: application/json' -d "@${PATCH_FILE}")

if [[ "${HTTP_CODE}" == "204" ]]; then
  echo "Account '${ACCOUNT}' has been changed successfully."
else
  echo "Account '${ACCOUNT}' update failed."
  echo "HTTP Code: ${HTTP_CODE}"
fi
