#!/bin/bash
# ==============================================================================
# Script Name: 10.routes_id_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script changes one property of a route's step, using the `/routes/{id}`
# endpoint with PATCH: a JSON Patch document that enables or disables the first
# step of a given type. Unlike PUT (09.routes_id_PUT.sh), it sends only what
# changes. A step is addressed by its position, so the script reads the route and
# finds the position first.
#
# Usage:
# ./10.routes_id_PATCH.sh NAME STEP_TYPE [STATUS]
#
#   NAME       the route (it must be the only one with that name)
#   STEP_TYPE  the type of the step, for example Compress or SendToPartner
#   STATUS     ENABLED or DISABLED (default DISABLED)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the status before, to put it back with.
# - Confirmed directly: the path is /steps/<position>/status. A step's id cannot be used
#   in its place (400 "Can't reference field ... on array"), a position past the end is
#   400 "Array index N is out of bounds", and a status other than ENABLED or DISABLED
#   is 400. A success answers 204, with no body.
# - Other things a patch of a route did, confirmed directly: `add` at /steps/- appends a
#   step, `add` at /steps/1 inserts one in the middle and the steps' precedingStep links
#   follow, `remove` at /steps/N deletes one, `replace` works on a description that is
#   null, `type` and `id` are read only (400), and a composite route's `routeTemplate`
#   cannot be changed (400).
# - Requires `jq`, which reads the id and builds the patch.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"
NAME="$1"
STEP_TYPE="$2"
[ -n "${NAME}" ] && [ -n "${STEP_TYPE}" ] || { printf "Usage: ./10.routes_id_PATCH.sh NAME STEP_TYPE [STATUS]\n"; exit 2; }
STATUS="${3:-DISABLED}"
[[ "${STATUS}" =~ ^(ENABLED|DISABLED)$ ]] || { printf "STATUS is ENABLED or DISABLED, not %s.\n" "${STATUS}"; exit 2; }

# The one route with that name: "1 <id>", or how many there are. The name filter
# takes a * wildcard, so the exact name is picked out of what comes back.
read -r FOUND ROUTE_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${NAME}" \
  --data-urlencode "fields=id,name" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s routes named %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}"
    exit 1
fi

# The position of the first step of that type, and its status now
read -r POSITION BEFORE < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ROUTE_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg type "${STEP_TYPE}" '(.steps // []) | to_entries | map(select(.value.type == $type)) | if length == 0 then "none" else "\(.[0].key) \(.[0].value.status)" end')
if [ "${POSITION}" = "none" ] || [ -z "${POSITION}" ]; then
    printf "The route %s has no step of type %s.\n" "${NAME}" "${STEP_TYPE}"
    exit 1
fi
printf "The %s step of %s is at position %s, and is %s.\n" "${STEP_TYPE}" "${NAME}" "${POSITION}" "${BEFORE}"
BODY=$(jq -n --arg path "/steps/${POSITION}/status" --arg value "${STATUS}" '[{op: "replace", path: $path, value: $value}]')

printf "Setting it to %s...\n" "${STATUS}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ROUTE_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
