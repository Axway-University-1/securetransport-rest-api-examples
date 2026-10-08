#!/bin/bash
# ==============================================================================
# Script Name: 04.zones_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves one zone using the `/zones/{name}` endpoint.
# It demonstrates:
# - Reading a zone by name, in full
# - A short summary: the edges with their protocols, proxies and addresses
# - Which business units name the zone (a business unit's `dmz` is the name of a zone)
#
# Usage:
# ./04.zones_name_GET.sh [NAME]
#
#   NAME  the zone (default example_zone, which 02 creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A zone is a NETWORK ZONE (a DMZ zone): it describes where the server's protocol servers are reached from. The lab has one,
#   `Private` ("This network zone holds the information for back ends", one edge `Host` with the lab's own FTP, SSH, HTTP, ADMIN,
#   AS2 and PESIT ports); a DMZ zone lists its edge servers in `edges` (title, addresses, protocols with ports, proxies). A zone is
#   addressed by its NAME in the path, and the name is case sensitive (`Private` is found, `private` is a 404). Never change or
#   delete `Private`: the examples default to an `example_*` zone, and the ones that change something need the name.
# - Confirmed directly: the answer is the zone itself: name, description, publicURLPrefix, ssoSpEntityId, isDnsResolutionEnabled, isDefault and
#   `edges`; an edge has edgeId, title, notes, deploymentSite, enabledProxy, configurationId, descriptor, protocols, proxies, isAutoDiscoverable,
#   dynamicNodeIpDiscoveryFqdn and ipAddresses. A proxy's `password` is always `null`; `isUsePassword` says whether one is saved. `fields=` keeps the
#   keys named (400 "Field bogus does not exist." for an unknown one). An unknown zone is a JSON 404 "Zone with name X not found.".
# - Confirmed directly: **using a zone**. A business unit names a zone in `dmz` (`POST /businessUnits` with `"dmz": "<zone>"`; a zone that does not
#   exist is 400 "No such DMZ zone with name X"). On the lab, with a zone that has an edge, an account of that unit logged in over SFTP and over the
#   EndUser API (HTTP) exactly as before: a zone does nothing to a login on a standalone server with no edge in front of it. What it does do: the zone
#   cannot be deleted while a unit names it (500 "Database error deleting DMZ zone"; delete works again once the unit is gone), and a
#   unit created while a zone was the default still read `dmz` null (the default flag is not copied into new units). The business units' own
#   `dmz=` filter answers 403 "unable to comply", so this script reads every unit's `dmz` and picks the ones that name the zone (the first 1000).
# - Requires `jq`, which URL-encodes the name and prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/zones"
NAME="${1:-example_zone}"
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read %s (HTTP %s):\n%s\n" "${NAME}" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"

printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '"  \(.name), default \(.isDefault), \(.edges | length) edge(s)", (.edges[] | "  edge \(.title): \((.protocols // []) | length) protocol(s), \((.proxies // []) | length) prox(ies), \((.ipAddresses // []) | length) address(es)")'
USING=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/businessUnits" \
  --data-urlencode "fields=name,dmz" --data-urlencode "limit=1000" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg zone "${NAME}" '[(.result // [])[] | select(.dmz == $zone) | .name] | join(", ")')
printf "  business units that name it: %s\n" "${USING:-none}"
