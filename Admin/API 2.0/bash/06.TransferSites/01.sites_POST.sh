#!/bin/bash
# ==============================================================================
# Script Name: 01.sites_POST.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a transfer site using the `/sites` endpoint.
#
# Usage:
# ./01.sites_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The site is attached to an account, which must already exist. This example
#   uses the account "john".
# - The host below points at ST_SERVER, which is only an example. A transfer
#   site normally points at a partner's server.
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

# Create TS
#
# Note that the payload is enclosed in double quotes so that ${ST_SERVER} is
# expanded by the shell. The inner double quotes of the JSON are escaped.
#
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites" -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d "{\"name\":\"HTTP\",\"type\":\"http\",\"protocol\":\"http\",\"account\":\"john\",\"host\":\"${ST_SERVER}\",\"port\":\"443\",\"downloadPattern\":\"*\",\"uploadFolder\":\"/\",\"userName\":\"john\"}"