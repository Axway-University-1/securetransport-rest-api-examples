#!/bin/bash
# ==============================================================================
# Script Name: 07.zones_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a zone using the `/zones/{name}` endpoint.
# It demonstrates:
# - Deleting a zone by name, and printing the server's reason when it refuses
#
# Usage:
# ./07.zones_name_DELETE.sh NAME
#
#   NAME  the zone to delete (required: never run it on `Private`, the back end's own zone)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: a success answers 204; deleting a zone that is not there is 404 "Zone with name X not found." (a second delete too). A zone
#   that a business unit still names as its `dmz` is refused with **500** "Database error deleting DMZ zone: X"; take the zone off the unit or delete the
#   unit first (see 04.zones_name_GET.sh for the units that name it). Deleting the default zone works.
# - Requires `jq`, which URL-encodes the name and prints the server's reason.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/zones"
NAME="$1"
[ -n "${NAME}" ] || { printf "Usage: ./07.zones_name_DELETE.sh NAME\n"; exit 2; }
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

printf "Deleting the zone %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
