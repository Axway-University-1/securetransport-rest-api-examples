#!/bin/bash
# ==============================================================================
# Script Name: 08.applications_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the Advanced Routing application the subscription belongs to, using the
# `/applications` endpoint. A subscription has to name an application that
# exists, and there is no application called AdvRouting on a new server.
#
# Usage:
# ./08.applications_POST.sh
#
# Risk: write
#
# Notes:
# - Requires `jq`, which builds the JSON body.
# - The application is called AR_APPLICATION in settings.sh.
# - The id is saved as AR_ID_APPLICATION, and 99.cleanup_DELETE.sh deletes it.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

BODY=$(jq -n --arg name "${AR_APPLICATION}" \
  '{type: "AdvancedRouting", name: $name, notes: ("Application for " + $name)}')

printf "Creating the application %s...\n" "${AR_APPLICATION}"
ar_admin_post "applications" "${BODY}" AR_ID_APPLICATION
