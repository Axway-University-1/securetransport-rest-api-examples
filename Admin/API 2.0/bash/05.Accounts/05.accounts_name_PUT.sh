#!/bin/bash
# ==============================================================================
# Script Name: 05.accounts_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script updates an account using the `/accounts/{name}` endpoint with the
# PUT method, which is the easiest way to update more than one property at once.
# It demonstrates:
# 1. GET to retrieve the object's content
# 2. jq to modify the parts we want
# 3. PUT to update the object's content
#
# Usage:
# ./05.accounts_name_PUT.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - PUT replaces the entire object, so all required fields must be preserved.
# - Requires `jq`, which is used to edit the retrieved JSON.
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
printf "Loading variables into our context..."
source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# The easiest way to update more than 1 property of an object is through the PUT method.

# For the example here, we will use
# 1. GET method to retrieve the object's content
# 2. jq to modify the parts we want
# 3. PUT method to update the object's content
#
# Requires `jq`. Editing the JSON with jq rather than with a text substitution
# targets the exact field and always produces valid JSON.

ACCOUNT="UserAccount"
NEW_UID="1111"

printf "Getting the account %s...\n" "${ACCOUNT}"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}" -H "accept: */*" -H "${REFERER_HEADER}" > result.json

printf "Changing the uid to %s...\n" "${NEW_UID}"
jq --arg newUid "${NEW_UID}" '.uid = $newUid' result.json > new_result.json

curl -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}" -H "accept: */*" -H "${REFERER_HEADER}" -H 'Content-Type: application/json' -d @new_result.json

# Remove the temporary API responses
rm -f result.json new_result.json