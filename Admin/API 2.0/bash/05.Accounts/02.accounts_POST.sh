#!/bin/bash
# ==============================================================================
# Script Name: 02.accounts_POST.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script creates accounts using the `/accounts` endpoint.
# It demonstrates creating one account of each type:
# - user
# - service
# - template
#
# Usage:
# ./02.accounts_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A template account needs a user class. This example uses "VirtClass",
#   but you can create your own and use it as the templateClass value.
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

# Simple POST to create an Account of type User
printf "Creating an Account of type User...\n\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d '{"name":"UserAccount","type":"user","homeFolder":"/home/UserAccount","uid":"41733","gid":"41733","user":{"name":"UserAccount","passwordCredentials":{"password":"1"}}}'


# Simple POST to create an Account of type Service
printf "Creating an Account of type Service...\n\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d '{"name":"ServiceAccount","type":"service","homeFolder":"/home/ServiceAccount","uid":"41733","gid":"41733"}'


# Simple POST to create an Account of type Template
# For the User Class we will select "VirtClass", but you can create your own and use it as a value of the templateClass property
printf "Creating an Account of type Template...\n\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d '{"name":"TemplateAccount","type":"template","homeFolder":"/home/TemplateAccount","uid":"41733","gid":"41733","templateClass": "VirtClass"}'