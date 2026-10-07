#!/bin/bash
# ==============================================================================
# Script Name: 08.routes_id_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a route exists, using the `/routes/{id}` endpoint with
# HEAD: 200 when it does, 404 when it does not. The path takes the route's id, so
# the script looks the id up by name first.
#
# Usage:
# ./08.routes_id_HEAD.sh [NAME]
#
#   NAME  the route (default SimpleRoute_Compress, which
#         03.routes_POST_simple_compress.sh creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The route is looked up by name, and must be the only one with that name.
# - Confirmed directly: HEAD answers 200 for a route of any type (simple, template or
#   composite) and 404, with no body, for an id that does not exist.
# - Requires `jq`, which reads the id.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"
NAME="${1:-SimpleRoute_Compress}"
# The one route with that name: "1 <id>", or how many there are. The name filter
# takes a * wildcard, so the exact name is picked out of what comes back.
read -r FOUND ROUTE_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${NAME}" \
  --data-urlencode "fields=id,name" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s routes named %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}"
    exit 1
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${ROUTE_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The route %s exists, id %s.\n" "${NAME}" "${ROUTE_ID}"
else
    printf "The route %s, id %s, does not exist (HTTP %s).\n" "${NAME}" "${ROUTE_ID}" "${HTTP_CODE}"
    exit 1
fi
