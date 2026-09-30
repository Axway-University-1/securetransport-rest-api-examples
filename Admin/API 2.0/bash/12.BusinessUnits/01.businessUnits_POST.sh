#!/bin/bash
# ==============================================================================
# Script Name: 01.businessUnits_POST.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a business unit using the `/businessUnits` endpoint.
#
# Usage:
# ./01.businessUnits_POST.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The baseFolder is the root under which the accounts of this business unit
#   are created.
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

# Create a Business Unit
curl -k -u ${ST_USER}:${ST_PASSWORD} -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/businessUnits" -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d '{"name":"Finance","baseFolder":"/home/fin"}'