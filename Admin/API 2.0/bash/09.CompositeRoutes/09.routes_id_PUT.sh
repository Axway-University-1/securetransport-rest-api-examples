#!/bin/bash
# ==============================================================================
# Script Name: 09.routes_id_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a route, using the `/routes/{id}` endpoint with PUT: it reads
# the route, changes its description, and sends the whole route back, steps
# included.
#
# Usage:
# ./09.routes_id_PUT.sh NAME [DESCRIPTION]
#
#   NAME         the route (it must be the only one with that name)
#   DESCRIPTION  the new description (default: Changed by 09.routes_id_PUT.sh)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the description before, to put it back with.
# - PUT replaces the whole route: a body with the name and type only answers 204 and
#   silently removes every step. That is why the route is read first, and sent back
#   with only the description changed. metadata, the read-only links, is left out.
# - Confirmed directly: a success answers 204, with no body. The steps keep their ids
#   when they are sent back with them. A route can be renamed by changing `name`, and
#   two simple routes may share a name. A body with another route's id or another
#   `type` is refused, 400. An unknown id is 404, a body without `type` or
#   `conditionType` 400.
# - Requires `jq`, which reads the id and edits the route.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"
NAME="$1"
[ -n "${NAME}" ] || { printf "Usage: ./09.routes_id_PUT.sh NAME [DESCRIPTION]\n"; exit 2; }
DESCRIPTION="${2:-Changed by 09.routes_id_PUT.sh}"

# The one route with that name: "1 <id>", or how many there are. The name filter
# takes a * wildcard, so the exact name is picked out of what comes back.
read -r FOUND ROUTE_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${NAME}" \
  --data-urlencode "fields=id,name" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s routes named %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}"
    exit 1
fi

ROUTE_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ROUTE_ID}" -H "accept: application/json" -H "${REFERER_HEADER}")
printf "The description of %s is now: %s\n" "${NAME}" "$(printf '%s' "${ROUTE_JSON}" | jq -r '.description // "(none)"')"
BODY=$(printf '%s' "${ROUTE_JSON}" | jq -c --arg description "${DESCRIPTION}" '.description = $description | del(.metadata)')

printf "Setting it to: %s\n" "${DESCRIPTION}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${ROUTE_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
