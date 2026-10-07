#!/bin/bash
# ==============================================================================
# Script Name: 04.accounts_name_GET.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves a single account using the `/accounts/{name}` endpoint.
# It demonstrates:
# - Retrieving the whole object
# - Selecting individual fields
# - Why the type is needed for fields that are specific to one account type
#
# Usage:
# ./04.accounts_name_GET.sh
#
# Risk: read
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

# Simple GET to retrieve everything about a specific account
echo "GET /api/v2.0/accounts/UserAccount"
curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/UserAccount" -H "accept: */*" -H "${REFERER_HEADER}"

# GET only the name, uid, and gid
# Pay attention that the type is also returned no matter that it is not specified in the fields
echo "GET /api/v2.0/accounts/UserAccount?fields=name,uid,gid"
curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/UserAccount?fields=name,uid,gid" -H "accept: */*" -H "${REFERER_HEADER}"

# If we want to receive fields that are not common to all account types, but are specific to the user one, we have to specify the type
# Let's try with the addressBookSettings and without the type
echo "GET /api/v2.0/accounts/UserAccount?fields=addressBookSettings"
curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/UserAccount?fields=addressBookSettings" -H "accept: */*" -H "${REFERER_HEADER}"

# And now by specifying the type=user
echo "GET /api/v2.0/accounts/UserAccount?type=user&fields=addressBookSettings"
curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/UserAccount?type=user&fields=addressBookSettings" -H "accept: */*" -H "${REFERER_HEADER}"