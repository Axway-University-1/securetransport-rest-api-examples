#!/bin/bash
# ==============================================================================
# Script Name: 06.routes_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves routes using the `/routes` endpoint.
# It demonstrates:
# - A GET request for the composite routes, kept to one account and printed as
#   one line per route, with the template and subscriptions it is linked to
# - A GET request for one route by its id, printing the type of each step
#
# Usage:
# ./06.routes_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This example uses the account "john" and the simple route
#   SimpleRoute_Compress, which 03.routes_POST_simple_compress.sh creates.
# - Requires `jq`, which prints the short listings.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"

ACCOUNT="john"
SIMPLE_ROUTE_NAME="SimpleRoute_Compress"

printf "The composite routes of '%s': id, name, template, subscriptions...\n" "${ACCOUNT}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/routes?type=COMPOSITE" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg account "${ACCOUNT}" \
    '(.result // [])[] | select(.account == $account)
     | "\(.id)  \(.name)  template=\(.routeTemplate)  subscriptions=\((.subscriptions // []) | join(","))"'

printf "\nThe steps of the simple route '%s'...\n" "${SIMPLE_ROUTE_NAME}"
SIMPLE_ROUTE_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/routes?fields=id&name=${SIMPLE_ROUTE_NAME}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')

if [ -z "${SIMPLE_ROUTE_ID}" ]; then
    printf "There is no route '%s'.\n" "${SIMPLE_ROUTE_NAME}"
    exit 0
fi

curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/routes/${SIMPLE_ROUTE_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.steps // [])[] | "  \(.type)  \(.status)"'
