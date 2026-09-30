#!/bin/bash
# ==============================================================================
# Script Name: 07.accounts_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes accounts using the `/accounts/{name}` endpoint.
# For each account it first checks whether the account exists with the HEAD
# method. If it exists, the account is deleted. Otherwise a message is printed.
#
# It cleans up the three accounts created by 02.accounts_POST.sh.
#
# Usage:
# ./07.accounts_name_DELETE.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This script deletes data. Check the account names before running it.
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

# Let's say that we want to delete an Account.
# For the purpose we will first check if it exists with the HEAD method. 
# If it exists, we will delete it.
# Otherwise will print message that it doesn't exist.


ACCOUNT_TO_CHECK="UserAccount"
HTTP_RESPONSE_CODE=$(curl -k -u ${ST_USER}:${ST_PASSWORD} --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT_TO_CHECK}" -H "accept: */*" -H "${REFERER_HEADER}" 2>&1 | grep HTTP | awk '{print $2}')

if [[ ${HTTP_RESPONSE_CODE} == "200" ]]; then
	printf "Deleting Account: ${ACCOUNT_TO_CHECK}\n\n"
	curl -k -u ${ST_USER}:${ST_PASSWORD} -X DELETE "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT_TO_CHECK}" -H "accept: */*" -H "${REFERER_HEADER}"
else
	echo "Account ${ACCOUNT_TO_CHECK} does not exist."
fi

ACCOUNT_TO_CHECK="ServiceAccount"
HTTP_RESPONSE_CODE=$(curl -k -u ${ST_USER}:${ST_PASSWORD} --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT_TO_CHECK}" -H "accept: */*" -H "${REFERER_HEADER}" 2>&1 | grep HTTP | awk '{print $2}')

if [[ ${HTTP_RESPONSE_CODE} == "200" ]]; then
	printf "Deleting Account: ${ACCOUNT_TO_CHECK}\n\n"
	curl -k -u ${ST_USER}:${ST_PASSWORD} -X DELETE "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT_TO_CHECK}" -H "accept: */*" -H "${REFERER_HEADER}"
else
	echo "Account ${ACCOUNT_TO_CHECK} does not exist."
fi

ACCOUNT_TO_CHECK="TemplateAccount"
HTTP_RESPONSE_CODE=$(curl -k -u ${ST_USER}:${ST_PASSWORD} --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT_TO_CHECK}" -H "accept: */*" -H "${REFERER_HEADER}" 2>&1 | grep HTTP | awk '{print $2}')
if [[ ${HTTP_RESPONSE_CODE} == "200" ]]; then
	printf "Deleting Account: ${ACCOUNT_TO_CHECK}\n\n"
	curl -k -u ${ST_USER}:${ST_PASSWORD} -X DELETE "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT_TO_CHECK}" -H "accept: */*" -H "${REFERER_HEADER}"
else
	echo "Account ${ACCOUNT_TO_CHECK} does not exist."
fi