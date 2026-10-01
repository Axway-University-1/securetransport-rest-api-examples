#!/bin/bash
# ==============================================================================
# Script Name: 06.routes_POST_template.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the route package template, using the `/routes` endpoint. A composite
# route (step 10) is built from a template, so it has to exist first.
#
# Usage:
# ./06.routes_POST_template.sh
#
# Notes:
# - Requires `jq`, which builds the JSON body.
# - The id is saved as AR_ID_TEMPLATE for the later steps.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

BODY=$(jq -n --arg name "${AR_TEMPLATE_ROUTE}" \
  '{name: $name, description: ("Package template for " + $name), type: "TEMPLATE", conditionType: "MATCH_ALL"}')

printf "Creating the route template %s...\n" "${AR_TEMPLATE_ROUTE}"
ar_admin_post "routes" "${BODY}" AR_ID_TEMPLATE
