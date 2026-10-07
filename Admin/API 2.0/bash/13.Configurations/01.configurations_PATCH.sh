#!/bin/bash
# ==============================================================================
# Script Name: 01.configurations_PATCH.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script changes a Server Configuration Option using the
# `/configurations/options/{name}` endpoint with the PATCH method.
#
# Usage:
# ./01.configurations_PATCH.sh
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - An option holds a list of values, so the path targets an index:
#   "/values/0" is the first value.
# - Changing a Server Configuration Option affects the whole server.
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

# Change Server Configuration Options
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations/options/AddressBook.Enabled" -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d '[{"op":"replace","path":"/values/0","value":"true"}]'