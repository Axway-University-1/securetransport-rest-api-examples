#!/bin/bash
# ==============================================================================
# Script Name: 05.applications_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the Advanced Routing application every subscription here belongs to,
# using the `/applications` endpoint. A subscription has to name an application
# that exists.
#
# Usage:
# ./05.applications_POST.sh
#
# Risk: write
#
# Notes:
# - Requires `jq`, which builds the JSON body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

BODY=$(jq -n --arg name "${BT_APPLICATION}" \
  '{type: "AdvancedRouting", name: $name, notes: ("Application for " + $name)}')

printf "Creating the application %s...\n" "${BT_APPLICATION}"
ar_admin_post "applications" "${BODY}"
