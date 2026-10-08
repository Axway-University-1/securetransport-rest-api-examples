#!/bin/bash
# ==============================================================================
# Script Name: 05.zones_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a zone using the `/zones/{name}` endpoint.
# It demonstrates:
# - Reading the zone, changing its description and sending the whole zone back (a PUT replaces it)
#
# Usage:
# ./05.zones_name_PUT.sh NAME [DESCRIPTION]
#
#   NAME         the zone to replace (required: never run it on `Private`)
#   DESCRIPTION  the new description (default "Replaced by the examples"), at most 255 characters
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the description before, to put it back with.
# - Confirmed directly: a success answers 204, with no body. **Send the whole zone back, as this script does.** A PUT replaces the zone, and what is
#   left out is reset: a body with only `name` and `description` set `publicURLPrefix`, `ssoSpEntityId` and `isDnsResolutionEnabled` back to null/false and
#   turned `isDefault` off (a default zone is no longer one); but a body with **no `edges` key keeps the edges**, `"edges": []` removes them all, and an edge listed
#   with only its `title` loses its notes, protocols, proxies, addresses and `enabledProxy`. `name` is required (400 "name must not be null") and must be the name
#   in the path: another one is 400 "Specified zone name does not match the one in the zone object.", so a PUT cannot rename a zone (nor can a PATCH of
#   `/name`). An unknown zone is 404 "Zone with name X not found". Sent back as it was read, a zone is kept as it was, the `edgeId`s and a proxy's
#   `isUsePassword` too, though the password reads `null`. `description` is 255 characters at most (400). An `isDefault` true makes this zone the only default.
# - Requires `jq`, which URL-encodes the name and edits the zone.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/zones"
NAME="$1"
[ -n "${NAME}" ] || { printf "Usage: ./05.zones_name_PUT.sh NAME [DESCRIPTION]\n"; exit 2; }
DESCRIPTION="${2:-Replaced by the examples}"
[ "${#DESCRIPTION}" -le 255 ] || { printf "DESCRIPTION is 255 characters at most.\n"; exit 2; }
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

ZONE_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${ZONE_JSON}" | jq -e '.name' >/dev/null 2>&1; then
    printf "There is no zone %s.\n" "${NAME}"
    exit 1
fi
printf "The description of %s is now: %s\n" "${NAME}" "$(printf '%s' "${ZONE_JSON}" | jq -r '.description // "(none)"')"
BODY=$(printf '%s' "${ZONE_JSON}" | jq -c --arg description "${DESCRIPTION}" '.description = $description')

printf "Setting it to: %s\n" "${DESCRIPTION}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
