#!/bin/bash
# ==============================================================================
# Script Name: 06.zones_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script partially updates a zone using the `/zones/{name}` endpoint.
# It demonstrates:
# - A JSON Patch that replaces one field, the description, and leaves the rest of the zone as it is
#
# Usage:
# ./06.zones_name_PATCH.sh NAME [DESCRIPTION]
#
#   NAME         the zone to change (required: never run it on `Private`)
#   DESCRIPTION  the new description (default "Patched by the examples"), at most 255 characters
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the description before, to put it back with.
# - Confirmed directly: a success answers 204, with no body. Unlike a PUT, a PATCH leaves everything it does not name as it was. `replace` worked
#   on a description that was null, and `remove` set it back to null; `add` on a field that is set worked too. Other paths that worked:
#   `/publicURLPrefix`, `/isDefault` (true makes it the only default zone, and false turns it off again), `/edges/0/notes`, `/edges/0/protocols/0/port`,
#   `/edges/-` (add an edge, which needs a `title`) and `remove` of `/edges/1`. A path that does not exist is 400 `Missing field "nope"`; `/name` is
#   400 "Specified zone name does not match the one in the zone object."; `/edges/0/edgeId` answers 204 and is ignored; an empty patch is 204; an unknown zone is 404.
#   Take care with an edge: a patch of its `title` makes the server treat it as another edge, and a proxy password it had saved is gone (`isUsePassword`
#   false); two edges with the same title are 500 "Database error updating zone."; a second protocol of the same kind on an edge is accepted.
# - Requires `jq`, which URL-encodes the name and builds the patch.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/zones"
NAME="$1"
[ -n "${NAME}" ] || { printf "Usage: ./06.zones_name_PATCH.sh NAME [DESCRIPTION]\n"; exit 2; }
DESCRIPTION="${2:-Patched by the examples}"
[ "${#DESCRIPTION}" -le 255 ] || { printf "DESCRIPTION is 255 characters at most.\n"; exit 2; }
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

BEFORE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}?fields=description" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.description // "(none)"')
printf "The description of %s is now: %s\n" "${NAME}" "${BEFORE}"
BODY=$(jq -cn --arg value "${DESCRIPTION}" '[{op: "replace", path: "/description", value: $value}]')

printf "Setting it to: %s\n" "${DESCRIPTION}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
