#!/bin/bash
# ==============================================================================
# Script Name: 07.routes_POST_simple.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the simple route that sends the pulled files to the push site, using
# the `/routes` endpoint. It is a single Send To Partner step. There is no
# Compress step: the files go on as they arrived.
#
# Usage:
# ./07.routes_POST_simple.sh
#
# Notes:
# - Requires `jq`, which builds the JSON body.
# - Run 03.sites_POST_push.sh first: the step names the push site.
# - The site is written as <site>#!#CVD#!# in transferSiteExpression. CVD is part
#   of the separator, not a name. Several sites are joined the same way:
#   <site1>#!#CVD#!#<site2>#!#CVD#!#
# - The id is saved as AR_ID_SIMPLE for the later steps.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

BODY=$(jq -n --arg name "${AR_SIMPLE_ROUTE}" --arg site "${AR_PUSH_SITE}" \
  '{type: "SIMPLE", name: $name, conditionType: "ALWAYS", condition: true,
    steps: [{type: "SendToPartner", status: "ENABLED", autostart: false,
             transferSiteExpressionType: "LIST",
             transferSiteExpression: ($site + "#!#CVD#!#"),
             fileFilterExpressionType: "GLOB", fileFilterExpression: "*",
             actionOnStepFailure: "FAIL"}]}')

printf "Creating the simple route %s...\n" "${AR_SIMPLE_ROUTE}"
ar_admin_post "routes" "${BODY}" AR_ID_SIMPLE
