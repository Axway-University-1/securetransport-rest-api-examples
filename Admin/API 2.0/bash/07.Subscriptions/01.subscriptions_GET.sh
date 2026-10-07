#!/bin/bash
# ==============================================================================
# Script Name: 01.subscriptions_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves subscriptions using the `/subscriptions` endpoint.
# A subscription links an account's folder to an application. It demonstrates:
# - A GET request for all the subscriptions of one account
# - A GET request filtered by type, printed as one line per subscription
#
# Usage:
# ./01.subscriptions_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This example uses the account "john". 02.subscriptions_POST.sh and
#   03.subscriptions_POST_triggerfile.sh create subscriptions for it.
# - Requires `jq`, which prints the short listing.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="john"

printf "Get all the subscriptions of the account '%s'...\n" "${ACCOUNT}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions?account=${ACCOUNT}" \
  -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nGet only its Advanced Routing subscriptions, one line each: id, folder, application...\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions?account=${ACCOUNT}&type=AdvancedRouting" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "\(.id)  \(.folder)  \(.application)"'
