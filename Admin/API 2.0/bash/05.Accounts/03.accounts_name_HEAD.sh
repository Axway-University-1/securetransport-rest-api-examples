#!/bin/bash
# ==============================================================================
# Script Name: 03.accounts_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether an account exists using the HEAD method on the
# `/accounts/{name}` endpoint.
# It demonstrates:
# - Sending a HEAD request
# - Capturing the HTTP response code
# - Acting on the result
#
# Usage:
# ./03.accounts_name_HEAD.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - HEAD returns the headers only, which makes it a cheap existence check.
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
printf "Loading variables into our context...\n\n"
source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT_TO_CHECK="UserAccount"
curl -k -u "${ST_USER}:${ST_PASSWORD}" --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT_TO_CHECK}" -H "accept: */*" -H "${REFERER_HEADER}"

# Or you can achieve the same thing with the '-I' option
# curl -k -u "${ST_USER}:${ST_PASSWORD}" -I "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT_TO_CHECK}" -H "accept: */*" -H "${REFERER_HEADER}"

# If you want to parse the response code, here is an example how to do it
# The ${HTTP_RESPONSE_CODE} variable will contain our HTTP Response code
HTTP_RESPONSE_CODE=$(curl -k -u "${ST_USER}:${ST_PASSWORD}" --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT_TO_CHECK}" -H "accept: */*" -H "${REFERER_HEADER}" 2>&1 | grep HTTP | awk '{print $2}')

# And this is the if statement that we will use to print "Account Exists" if the HTTP Reponse Code is equal to 200
if [[ ${HTTP_RESPONSE_CODE} == "200" ]]; then
	echo "Account Exists"
fi

# An alternative version with if-else contruction
if [[ ${HTTP_RESPONSE_CODE} == "200" ]]; then
	echo "Account Exists"
else
	echo "Account does not exist"
fi