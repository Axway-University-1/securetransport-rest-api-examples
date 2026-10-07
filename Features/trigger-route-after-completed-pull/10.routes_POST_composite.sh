#!/bin/bash
# ==============================================================================
# Script Name: 10.routes_POST_composite.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the composite route that ties it together, using the `/routes` endpoint.
# It is built from the template, is attached to the subscription, and has one
# ExecuteRoute step that runs the simple route.
#
# Usage:
# ./10.routes_POST_composite.sh
#
# Risk: write
#
# Notes:
# - Requires `jq`, which builds the JSON body.
# - Needs the ids saved by steps 6, 7 and 9.
# - The id is saved as AR_ID_COMPOSITE for the cleanup.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

if [ -z "$(ar_state_get AR_ID_TEMPLATE)" ]; then
    printf "AR_ID_TEMPLATE is not saved. Run step 6 first.\n"
    exit 1
fi

if [ -z "$(ar_state_get AR_ID_SIMPLE)" ]; then
    printf "AR_ID_SIMPLE is not saved. Run step 7 first.\n"
    exit 1
fi

if [ -z "$(ar_state_get AR_ID_SUBSCRIPTION)" ]; then
    printf "AR_ID_SUBSCRIPTION is not saved. Run step 9 first.\n"
    exit 1
fi

BODY=$(jq -n --arg name "${AR_COMPOSITE_ROUTE}" --arg account "${AR_TEST_ACCOUNT}" \
  --arg template "$(ar_state_get AR_ID_TEMPLATE)" \
  --arg simple "$(ar_state_get AR_ID_SIMPLE)" \
  --arg subscription "$(ar_state_get AR_ID_SUBSCRIPTION)" \
  '{type: "COMPOSITE", account: $account, name: $name, conditionType: "MATCH_ALL",
    routeTemplate: $template, subscriptions: [$subscription],
    steps: [{type: "ExecuteRoute", status: "ENABLED", autostart: false, executeRoute: $simple}]}')

printf "Creating the composite route %s...\n" "${AR_COMPOSITE_ROUTE}"
ar_admin_post "routes" "${BODY}" AR_ID_COMPOSITE
