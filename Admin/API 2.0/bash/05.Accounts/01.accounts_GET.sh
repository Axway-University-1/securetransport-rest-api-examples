#!/bin/bash
# ==============================================================================
# Script Name: 01.accounts_GET.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves accounts using the `/accounts` endpoint.
# It demonstrates:
# - Retrieving all accounts
# - Filtering by account type
# - Selecting individual fields
# - Limiting the number of results
#
# Usage:
# ./01.accounts_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The type is always returned, even when it is not listed in the fields.
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



# Simple GET to retrieve all available Accounts
curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" -H "accept: */*" -H "${REFERER_HEADER}"


# GET only the Accounts of type user
# You can also try with type=template or type=service
# curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts?type=user" -H "accept: */*" -H "${REFERER_HEADER}"

# GET the User Accounts and receive only the name and home folder in the response
# Pay attention that the type is also returned no matter that it is not specified in the fields
# curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts?type=user&fields=name,homeFolder" -H "accept: */*" -H "${REFERER_HEADER}"

# If the result is still big to analyze, you can use the limit parameter to get the first 5 elements
# curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts?type=user&fields=name,homeFolder&limit=5" -H "accept: */*" -H "${REFERER_HEADER}"